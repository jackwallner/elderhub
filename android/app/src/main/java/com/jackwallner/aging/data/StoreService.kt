package com.jackwallner.aging.data

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.aging.BuildConfig
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Offering
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PackageType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesException
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitLogIn
import com.revenuecat.purchases.awaitLogOut
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.models.Period
import com.revenuecat.purchases.paywalls.events.CustomPaywallImpressionParams
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay

enum class PurchaseOutcome { PURCHASED, PENDING, CANCELLED }

class PurchaseException(message: String) : Exception(message)

internal fun purchaseOutcome(code: PurchasesErrorCode, userCancelled: Boolean): PurchaseOutcome? = when {
    userCancelled || code == PurchasesErrorCode.PurchaseCancelledError -> PurchaseOutcome.CANCELLED
    code == PurchasesErrorCode.PaymentPendingError -> PurchaseOutcome.PENDING
    else -> null
}

/** Product ids shared with iOS; the Play subscription ids match, base plans are `monthly`/`yearly`. */
object ProProduct {
    const val MONTHLY = "com.jackwallner.aging.pro.monthly"
    const val YEARLY = "com.jackwallner.aging.pro.yearly"
    const val LIFETIME = "com.jackwallner.aging.pro.lifetime"
    val all = listOf(MONTHLY, YEARLY, LIFETIME)

    /** Entitlement as configured in RevenueCat. "Aging+", not the fleet default "pro". */
    const val ENTITLEMENT = "Aging+"
    val FALLBACK_ENTITLEMENTS = listOf("pro", "AgingPro")

    /** Active when the main entitlement or a legacy alias is active. */
    fun isEntitled(activeEntitlements: Set<String>): Boolean =
        ENTITLEMENT in activeEntitlements || FALLBACK_ENTITLEMENTS.any { it in activeEntitlements }
}

/**
 * RevenueCat behind the `Aging+` entitlement, shown as Elderhub Plus. Debug
 * builds use the Test Store key and release builds the Play key; neither ever
 * runs on the other. The paywall reads every price and trial from the store.
 */
class StoreService(private val context: Context, private val defaults: KeyValueStore) {
    private val reviewAccess = ReviewAccess(defaults, BuildConfig.PLAY_REVIEW_CODE_SHA256)
    private var entitlementActive by mutableStateOf(false)
    private var reviewGranted by mutableStateOf(reviewAccess.isGranted)
    private var forcePro by mutableStateOf(false)

    /** The single gate the whole app reads. */
    val isPro: Boolean get() = entitlementActive || reviewGranted || forcePro

    var isConfigured by mutableStateOf(false)
        private set
    var isLoading by mutableStateOf(false)
        private set
    var hasAttemptedLoad by mutableStateOf(false)
        private set
    var loadFailure by mutableStateOf<String?>(null)
        private set
    var plans by mutableStateOf<List<Plan>>(emptyList())
        private set
    var hasSubscriptionHistory by mutableStateOf(false)
        private set
    var introEligibilityResolved by mutableStateOf(false)
        private set

    private var packages: List<Package> = emptyList()
    private var offering: Offering? = null
    private var isPreview = false
    private val impressionsThisSession = mutableSetOf<String>()

    val isLoadingPlans: Boolean get() = plans.isEmpty() && (isLoading || !hasAttemptedLoad)
    val hasNoPlans: Boolean get() = plans.isEmpty() && hasAttemptedLoad && !isLoading

    /** Days of free trial this account would actually get, or null. Never promised before eligibility resolves. */
    fun eligibleTrialDays(plan: Plan?): Int? {
        val trial = plan?.trial ?: return null
        if (!introEligibilityResolved || hasSubscriptionHistory) return null
        return trial.days
    }

    // MARK: - Debug and review access

    fun forceProForDebug(value: Boolean = true) {
        if (!BuildConfig.DEBUG) return
        forcePro = value
    }

    /** Debug screenshots and UI tests: a local plan stack with no store behind it. */
    fun loadPreviewPlans(plans: List<Plan>, history: Boolean = false) {
        if (!BuildConfig.DEBUG) return
        this.plans = PaywallCopy.ordered(plans)
        packages = emptyList()
        hasSubscriptionHistory = history
        introEligibilityResolved = true
        hasAttemptedLoad = true
        isConfigured = true
        isPreview = true
        loadFailure = null
    }

    fun activateReviewAccess(code: String): Boolean {
        if (!reviewAccess.activate(code)) return false
        reviewGranted = true
        return true
    }

    // MARK: - Store

    suspend fun start() {
        if (!configureIfNeeded()) {
            hasAttemptedLoad = true
            return
        }
        refreshCustomerInfo()
        refresh()
    }

    suspend fun refreshCustomerInfo() {
        if (!configureIfNeeded() || isPreview) return
        runCatching { Purchases.sharedInstance.awaitCustomerInfo() }
            .onSuccess(::apply)
            .onFailure { if (it is CancellationException) throw it }
    }

    suspend fun refresh() {
        if (isPreview) return
        if (!configureIfNeeded()) {
            hasAttemptedLoad = true
            loadFailure = UNAVAILABLE
            return
        }
        if (isLoading) {
            while (isLoading) delay(50)
            return
        }
        isLoading = true
        try {
            val offerings = Purchases.sharedInstance.awaitOfferings()
            val offering = offerings.all[ANDROID_OFFERING_ID] ?: offerings.current
            val loaded = offering?.availablePackages.orEmpty()
            this.offering = offering
            packages = loaded
            plans = PaywallCopy.ordered(loaded.map(::plan))
            loadFailure = if (loaded.isEmpty()) "No plans came back from Google Play." else null
            refreshCustomerInfo()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Throwable) {
            packages = emptyList()
            plans = emptyList()
            loadFailure = UNAVAILABLE
        } finally {
            isLoading = false
            hasAttemptedLoad = true
        }
    }

    fun trackPaywallImpression(id: String) {
        if (!impressionsThisSession.add(id)) return
        if (!isConfigured || isPreview) return
        val params = offering?.let { CustomPaywallImpressionParams(id, it) } ?: CustomPaywallImpressionParams(id)
        runCatching { Purchases.sharedInstance.trackCustomPaywallImpression(params) }
    }

    /** A cancel is an outcome, not an error. Throws only with a user-facing message. */
    suspend fun purchase(activity: Activity, plan: Plan?): PurchaseOutcome {
        if (isPreview && plan != null) {
            forcePro = true
            return PurchaseOutcome.PURCHASED
        }
        val pkg = plan?.let { p -> packages.firstOrNull { it.identifier == p.packageId } }
        if (!configureIfNeeded() || pkg == null) throw PurchaseException(UNAVAILABLE)
        val withTrial = eligibleTrialDays(plan) != null
        val option = if (withTrial) pkg.product.defaultOption else pkg.product.subscriptionOptions?.basePlan
        val params = if (option != null) {
            PurchaseParams.Builder(activity, option).presentedOfferingContext(pkg.presentedOfferingContext).build()
        } else PurchaseParams.Builder(activity, pkg).build()
        return try {
            val result = Purchases.sharedInstance.awaitPurchase(params)
            apply(result.customerInfo)
            if (entitlementActive) PurchaseOutcome.PURCHASED else PurchaseOutcome.PENDING
        } catch (error: PurchasesTransactionException) {
            purchaseOutcome(error.code, error.userCancelled)
                ?: throw PurchaseException("Couldn't complete the purchase. Please try again.")
        }
    }

    /**
     * The RevenueCat customer carries the Supabase user id once signed in, so
     * the webhook can credit the circle (`group_billing`) and every sibling's
     * phone unlocks. Before sign-in the customer is anonymous, as on iOS.
     */
    suspend fun identify(userId: String) {
        if (!configureIfNeeded() || isPreview) return
        runCatching { apply(Purchases.sharedInstance.awaitLogIn(userId).customerInfo) }
            .onFailure { if (it is CancellationException) throw it }
    }

    /** Sign-out and account deletion: the next purchase must not credit the account that left. */
    suspend fun forgetCustomer() {
        if (!configureIfNeeded() || isPreview) return
        if (Purchases.sharedInstance.isAnonymous) return
        runCatching { apply(Purchases.sharedInstance.awaitLogOut()) }
            .onFailure { if (it is CancellationException) throw it }
    }

    /** Returns the message to show: restored, nothing found, or why it failed. */
    suspend fun restorePurchases(): String {
        if (isPreview) return if (isPro) RESTORED else NOTHING_TO_RESTORE
        if (!configureIfNeeded()) return UNAVAILABLE
        return try {
            apply(Purchases.sharedInstance.awaitRestore())
            if (entitlementActive) RESTORED else NOTHING_TO_RESTORE
        } catch (error: CancellationException) {
            throw error
        } catch (error: PurchasesException) {
            if (error.code == PurchasesErrorCode.PaymentPendingError) {
                "Google Play is still processing your payment. Elderhub Plus unlocks as soon as it completes."
            } else "Couldn't restore purchases. Try again."
        } catch (_: Throwable) {
            "Couldn't restore purchases. Try again."
        }
    }

    private fun apply(info: CustomerInfo) {
        hasSubscriptionHistory = info.allExpirationDatesByProduct.isNotEmpty()
        introEligibilityResolved = true
        entitlementActive = ProProduct.isEntitled(info.entitlements.active.keys)
    }

    private fun configureIfNeeded(): Boolean {
        if (isConfigured) return true
        val key = BuildConfig.REVENUECAT_API_KEY
        if (key.isBlank()) return false
        // Never the production Play key in a debug build, and never a test key in release.
        if (BuildConfig.DEBUG && key.startsWith("goog_")) return false
        if (!BuildConfig.DEBUG && !key.startsWith("goog_")) return false
        Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.ERROR
        val builder = PurchasesConfiguration.Builder(context, key)
        // Test Store runs share one tester so test installs don't inflate the
        // live project's customer charts. Never with the Play key: real buyers
        // would share one identity.
        if (key.startsWith("test_")) builder.appUserID(QA_APP_USER_ID)
        Purchases.configure(builder.build())
        Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener { apply(it) }
        isConfigured = true
        return true
    }

    private fun kind(pkg: Package): PackageKind = when (pkg.packageType) {
        PackageType.LIFETIME -> PackageKind.LIFETIME
        PackageType.ANNUAL -> PackageKind.YEARLY
        PackageType.MONTHLY -> PackageKind.MONTHLY
        else -> PackageKind.fromIdentifiers(pkg.identifier, pkg.product.id)
    }

    private fun plan(pkg: Package): Plan {
        val price = pkg.product.price
        val free = pkg.product.subscriptionOptions?.firstOrNull { it.freePhase != null }?.freePhase
            ?: pkg.product.defaultOption?.freePhase
        return Plan(
            packageId = pkg.identifier,
            productId = pkg.product.id,
            kind = kind(pkg),
            priceMicros = price.amountMicros,
            priceFormatted = price.formatted,
            currencyCode = price.currencyCode,
            period = pkg.product.period?.toPlanPeriod(),
            trial = free?.billingPeriod?.toPlanPeriod(),
            title = pkg.product.title,
        )
    }

    private fun Period.toPlanPeriod(): PlanPeriod? {
        val unit = when (unit) {
            Period.Unit.DAY -> PeriodUnit.DAY
            Period.Unit.WEEK -> PeriodUnit.WEEK
            Period.Unit.MONTH -> PeriodUnit.MONTH
            Period.Unit.YEAR -> PeriodUnit.YEAR
            else -> return null
        }
        return PlanPeriod(value, unit)
    }

    companion object {
        private const val ANDROID_OFFERING_ID = "android"
        private const val QA_APP_USER_ID = "qa-android"
        const val UNAVAILABLE = "Google Play isn't reachable right now. Check your connection and try again."
        const val RESTORED = "Elderhub Plus is active on this phone."
        const val NOTHING_TO_RESTORE = "No Elderhub Plus purchase was found for this Google Play account."
    }
}
