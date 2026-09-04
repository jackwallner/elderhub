import Foundation
import StoreKit
import os
@preconcurrency import RevenueCat

/// One purchasable plan, decoupled from where it came from.
///
/// On device the source is a RevenueCat `Package`. On the simulator RevenueCat is
/// never configured (see `configureIfNeeded`), so plans come straight from
/// StoreKit Testing instead. Without this the paywall can only ever render its
/// empty state on a sim, which makes the layout unverifiable.
/// How long one purchase covers, which is the fact the paywall needs in order
/// to compare two prices honestly. Derived from the product id rather than
/// parsed out of a localized string.
enum PlanPeriod: Sendable {
    case monthly, yearly, lifetime

    /// Months covered. Nil for lifetime, which has no per-month price and must
    /// not be given a fake one.
    var months: Int? {
        switch self {
        case .monthly: return 1
        case .yearly: return 12
        case .lifetime: return nil
        }
    }
}

struct PlanOption: Identifiable, Sendable {
    let id: String
    let title: String
    /// Already localized by StoreKit. Never rebuilt from `amount`.
    let price: String
    /// The raw figure, so the paywall can divide it. Kept alongside the
    /// formatted string rather than replacing it: currency formatting is
    /// StoreKit's job and getting it wrong is a compliance problem, not a
    /// cosmetic one.
    let amount: Decimal
    let currencyCode: String
    let period: PlanPeriod
    let package: Package?
    /// Days of free trial this product's introductory offer grants, or nil when
    /// it has no free-trial offer. Read off the store's own subscription period
    /// rather than hard-coded, so changing the offer in ASC changes every line
    /// of copy on the paywall without a new build. Eligibility is a separate
    /// question: this is what the *product* offers, not what *this Apple ID*
    /// would be granted. Ask `StoreService.eligibleTrialDays(for:)` before
    /// putting the word "trial" on screen.
    let trialDays: Int?

    /// "$4.08 / month" for a yearly plan, so the two subscriptions can be
    /// compared without arithmetic. Nil for a one-off purchase.
    func perMonthLabel() -> String? {
        guard let months = period.months, months > 1, amount > 0 else { return nil }
        let perMonth = amount / Decimal(months)
        return perMonth.formatted(.currency(code: currencyCode).precision(.fractionLength(2)))
    }

    /// Whole per cent saved by paying for this plan instead of twelve months of
    /// `monthly`. Nil unless this is the yearly plan and it genuinely costs
    /// less, so the badge is never invented.
    ///
    /// Rounded **down**, and deliberately not via `Int(truncating:)`: that
    /// returns 0 for a Decimal carrying a long fraction (66.641641…), which is
    /// what kept this badge off the paywall entirely.
    func savingsPercent(against monthly: PlanOption?) -> Int? {
        guard period == .yearly,
              let monthly, monthly.period == .monthly, monthly.amount > 0 else { return nil }
        let twelveMonths = monthly.amount * 12
        guard amount < twelveMonths else { return nil }
        let saved = (twelveMonths - amount) / twelveMonths * 100
        let percent = Int((saved as NSDecimalNumber).doubleValue)
        return percent > 0 ? percent : nil
    }

    /// Free-trial length from a RevenueCat introductory offer.
    ///
    /// Only `.freeTrial` counts. A pay-up-front or pay-as-you-go introductory
    /// *price* is a discount, and selling one as a free trial is an Apple 3.1.2
    /// problem rather than a wording preference.
    static func freeTrialDays(from discount: RevenueCat.StoreProductDiscount?) -> Int? {
        guard let discount, discount.paymentMode == .freeTrial else { return nil }
        let period = discount.subscriptionPeriod
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }

    /// The StoreKit-Testing equivalent, for the simulator, where RevenueCat is
    /// never configured and the offer comes from the local `.storekit` catalog.
    static func freeTrialDays(from offer: StoreKit.Product.SubscriptionOffer?) -> Int? {
        guard let offer, offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        case .year: return period.value * 365
        @unknown default: return nil
        }
    }
}

enum ProProduct {
    static let monthly = "com.jackwallner.aging.pro.monthly"
    static let yearly = "com.jackwallner.aging.pro.yearly"
    static let lifetime = "com.jackwallner.aging.pro.lifetime"
    static let all: [String] = [monthly, yearly, lifetime]

    static func title(for productID: String) -> String {
        switch productID {
        case monthly: return "Monthly"
        case yearly: return "Yearly"
        case lifetime: return "Lifetime"
        default: return "Elderhub Plus"
        }
    }

    static func period(for productID: String) -> PlanPeriod {
        switch productID {
        case yearly: return .yearly
        case lifetime: return .lifetime
        default: return .monthly
        }
    }

    /// Cheapest commitment first, so the list reads the same way every time
    /// regardless of what order RevenueCat hands the packages back in.
    static func order(for productID: String) -> Int {
        all.firstIndex(of: productID) ?? all.count
    }
}

enum RevenueCatConfig {
    static let apiKey = "appl_dvyPWLaZxKyjLUrFVzDynNGjVGb"
    /// Entitlement identifier as configured on the RevenueCat dashboard. It is
    /// "Aging+" here, not the fleet-default "pro", so checking only "pro" would
    /// leave a paying customer locked out.
    static let proEntitlement = "Aging+"
    /// Kept so a purchase made against an alternate identifier still unlocks.
    static let fallbackEntitlements = ["pro", "AgingPro"]
}

/// Freemium gate. Every care feature is free for one person. Plus unlocks
/// additional people in the same care circle.
@MainActor
@Observable
final class StoreService: NSObject {
    static let shared = StoreService()

    private(set) var isPro: Bool = false
    private(set) var offerings: Offerings?
    private(set) var plans: [PlanOption] = []
    private(set) var isLoading: Bool = false

    /// Why the last load produced no plans, or nil if it produced some.
    ///
    /// Only logged before, which made the paywall's one empty branch mean two
    /// opposite things: "the prices are a moment away" and "the store could not
    /// be reached and never will be on its own". It rendered a bare spinner for
    /// both, so a failure was an animation that never stopped. That matters
    /// more here than in most apps, because this one is built to be opened with
    /// no signal, so the failing case is ordinary rather than exotic. The
    /// paywall now reads this to decide between waiting and offering a retry.
    private(set) var loadFailure: String?

    /// Whether a load has ever finished. Without it the paywall cannot tell
    /// "about to start" from "tried and failed", and the failure state flashes
    /// up for a frame before the first attempt has even run.
    private(set) var hasAttemptedLoad: Bool = false

    /// True only for the honest in-between: nothing to show yet, and either a
    /// load is running or the first one has not started.
    var isLoadingPlans: Bool { plans.isEmpty && (isLoading || !hasAttemptedLoad) }

    /// True when an attempt has finished and left the sheet with nothing to
    /// sell. Retry is the only useful thing to offer here.
    var hasNoPlans: Bool { plans.isEmpty && hasAttemptedLoad && !isLoading }

    /// Whether *this* Apple ID would actually be granted each product's
    /// introductory offer. A trial already used on the account is still
    /// advertised by the product, so without this the paywall promises a free
    /// week and charges on the spot — the failure Apple 3.1.2 is about.
    private(set) var introEligibility: [String: Bool] = [:]
    /// True once the first eligibility check has finished, successfully or not.
    /// Until then every trial line stays off: silence is recoverable, a promise
    /// the store will not honour is not.
    private(set) var introEligibilityResolved: Bool = false

    private var isConfigured = false
    private var paywallImpressionsThisSession: Set<String> = []
    private var localOverride: Bool?
    private let log = Logger(subsystem: "com.jackwallner.aging", category: "store")

    private override init() {
        super.init()
    }

    /// Dev/sim escape hatch so paywalled screens can be driven without a purchase.
    func setLocalOverride(isPro value: Bool?) {
        localOverride = value
        if let value {
            isPro = value
        }
    }

    func start() {
        configureIfNeeded()
        Task {
            await identify()
            await refresh()
        }
    }

    /// Ties the RevenueCat customer to the Supabase user id, which is what makes
    /// the webhook able to find the payer's group. Without this the webhook sees
    /// an anonymous RevenueCat id, has nobody to credit, and the family silently
    /// never gets Plus.
    func identify() async {
        guard isConfigured, let userID = AuthService.shared.userID else { return }
        do {
            let (info, _) = try await Purchases.shared.logIn(userID.uuidString)
            apply(info)
        } catch {
            log.error("logIn failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Drops the RevenueCat identity when the account boundary closes.
    ///
    /// Sign-out used to leave the previous user logged in to RevenueCat, so the
    /// next account on the handset inherited their entitlement state and any
    /// purchase made afterwards was attributed to the person who signed out.
    /// `logOut` puts the SDK back on an anonymous id; the observable state is
    /// reset with it rather than left showing Plus for a family that has gone.
    func forgetCustomer() async {
        guard isConfigured else {
            isPro = localOverride ?? false
            return
        }
        do {
            let info = try await Purchases.shared.logOut()
            apply(info)
        } catch {
            log.error("logOut failed: \(error.localizedDescription, privacy: .public)")
            isPro = localOverride ?? false
        }
    }

    func refresh() async {
        if let localOverride {
            isPro = localOverride
        }

        isLoading = true
        defer {
            isLoading = false
            hasAttemptedLoad = true
        }

        guard isConfigured else {
            // Simulator: no RevenueCat, so fall back to StoreKit Testing products.
            await loadStoreKitTestingPlans()
            await refreshIntroEligibility()
            return
        }

        loadFailure = nil
        do {
            let info = try await Purchases.shared.customerInfo()
            apply(info)
            let offerings = try await Purchases.shared.offerings()
            self.offerings = offerings
            plans = (offerings.current?.availablePackages ?? []).map {
                PlanOption(
                    id: $0.storeProduct.productIdentifier,
                    title: ProProduct.title(for: $0.storeProduct.productIdentifier),
                    price: $0.storeProduct.localizedPriceString,
                    amount: $0.storeProduct.price,
                    currencyCode: $0.storeProduct.currencyCode ?? Locale.current.currency?.identifier ?? "USD",
                    period: ProProduct.period(for: $0.storeProduct.productIdentifier),
                    package: $0,
                    trialDays: PlanOption.freeTrialDays(from: $0.storeProduct.introductoryDiscount)
                )
            }
            .sorted { ProProduct.order(for: $0.id) < ProProduct.order(for: $1.id) }

            // A load that succeeds and returns nothing is still a failure from
            // the reader's side: the sheet is open and has nothing to sell. It
            // happens when the offering is misconfigured, which no amount of
            // waiting fixes, so it must not be left looking like loading.
            if plans.isEmpty {
                loadFailure = "No plans came back from the App Store."
            }
        } catch {
            log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
            loadFailure = error.localizedDescription
        }
        await refreshIntroEligibility()
    }

    /// Asks the store which advertised trials this account would really get.
    ///
    /// Cheap enough to re-run whenever the paywall opens, and worth it: the
    /// answer changes the moment the user starts a trial on another device.
    func refreshIntroEligibility() async {
        let withTrial = plans.filter { $0.trialDays != nil }
        guard !withTrial.isEmpty else {
            introEligibility = [:]
            introEligibilityResolved = true
            return
        }

        guard isConfigured else {
            // Simulator: there is no RevenueCat customer to ask, and StoreKit
            // Testing starts each run with a clean purchase history, so what the
            // catalog advertises is what would be granted. This is also what
            // makes the trial layout visible in the paywall render test.
            introEligibility = Dictionary(uniqueKeysWithValues: withTrial.map { ($0.id, true) })
            introEligibilityResolved = true
            return
        }

        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(
            productIdentifiers: withTrial.map(\.id)
        )
        introEligibility = result.mapValues { $0.status == .eligible }
        introEligibilityResolved = true
    }

    /// The trial length to advertise for a plan, or nil when none may be.
    ///
    /// The single accessor the paywall uses, so headline, plan row, CTA,
    /// timeline and disclosure cannot drift apart from each other or from what
    /// StoreKit will grant. Returns nil until eligibility resolves.
    func eligibleTrialDays(for plan: PlanOption) -> Int? {
        guard let days = plan.trialDays, introEligibilityResolved else { return nil }
        return introEligibility[plan.id] == true ? days : nil
    }

    /// Populates `plans` from the local `.storekit` catalog. Only ever runs when
    /// RevenueCat is not configured, i.e. on the simulator.
    private func loadStoreKitTestingPlans() async {
        loadFailure = nil
        do {
            let products = try await Product.products(for: ProProduct.all)
            let order = ProProduct.all
            plans = products
                .sorted { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
                .map {
                    PlanOption(
                        id: $0.id,
                        title: ProProduct.title(for: $0.id),
                        price: $0.displayPrice,
                        amount: $0.price,
                        currencyCode: $0.priceFormatStyle.currencyCode,
                        period: ProProduct.period(for: $0.id),
                        package: nil,
                        trialDays: PlanOption.freeTrialDays(from: $0.subscription?.introductoryOffer)
                    )
                }
            if plans.isEmpty {
                loadFailure = "No plans came back from the App Store."
            }
        } catch {
            log.error("StoreKit Testing load failed: \(error.localizedDescription, privacy: .public)")
            loadFailure = error.localizedDescription
        }
    }

    func purchase(_ plan: PlanOption) async throws {
        guard let package = plan.package else {
            // StoreKit Testing render only; there is nothing to charge against.
            return
        }
        let startedTrial = package.storeProduct.introductoryDiscount?.paymentMode == .freeTrial
        let result = try await Purchases.shared.purchase(package: package)
        guard !result.userCancelled else { return }
        apply(result.customerInfo)
        if isPro {
            ConversionDiagnostics.recordConversion(
                plan: package.storeProduct.productIdentifier,
                startedTrial: startedTrial,
                offeringID: package.presentedOfferingContext.offeringIdentifier
            )
            syncConversionAttributes()
        }
        await propagateToGroup()
    }

    /// Reports a custom-paywall impression to RevenueCat and records the
    /// on-device funnel tally.
    ///
    /// This app previously reported no impressions at all, so everything
    /// between "installed" and "subscribed" was invisible for it.
    ///
    /// Attributes rather than extra impressions for the funnel steps: RevenueCat
    /// treats every impression id as a paywall encounter, so pushing steps
    /// through that channel would drive the encounter rate to 100% and destroy
    /// the one server-side number that works.
    ///
    /// `isConfigured` is the load-bearing guard: `Purchases.shared` traps when
    /// RevenueCat was never configured, which is every simulator run.
    func trackPaywallImpression(id: String, oncePerSession: Bool = false) {
        configureIfNeeded()
        guard isConfigured else { return }
        if oncePerSession {
            guard !paywallImpressionsThisSession.contains(id) else { return }
            paywallImpressionsThisSession.insert(id)
        }
        ConversionDiagnostics.recordPitchView(impressionID: id)
        syncConversionAttributes()
        Purchases.shared.trackCustomPaywallImpression(
            CustomPaywallImpressionParams(paywallId: id)
        )
    }

    /// `setAttributes` only queues. RevenueCat uploads when the app backgrounds
    /// or folds the queue into the POST that creates a customer, so a probe run
    /// has to background the app before reading anything back.
    func syncConversionAttributes() {
        guard isConfigured else { return }
        let attributes = ConversionDiagnostics.subscriberAttributes
        guard !attributes.isEmpty else { return }
        Purchases.shared.attribution.setAttributes(attributes)
    }

    func restore() async throws {
        guard isConfigured else { return }
        let info = try await Purchases.shared.restorePurchases()
        apply(info)
        await propagateToGroup()
    }

    /// The webhook is what actually writes `group_billing`, and it arrives
    /// server-to-server a moment later. This pulls the row so the rest of the
    /// family's entitlement is current on the payer's own device too, and so
    /// `hasPlus` is right if they hand the phone to someone.
    private func propagateToGroup() async {
        // Give the webhook a beat to land. Not load-bearing: the payer is
        // already unlocked locally either way, and the next foreground refresh
        // picks it up regardless.
        try? await Task.sleep(for: .seconds(2))
        await GroupService.shared.refreshBilling()
    }

    private func apply(_ info: CustomerInfo) {
        guard localOverride == nil else { return }
        let identifiers = [RevenueCatConfig.proEntitlement] + RevenueCatConfig.fallbackEntitlements
        isPro = identifiers.contains { info.entitlements[$0]?.isActive == true }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        // Agent/simulator runs must never create customers in the production
        // RevenueCat project. Use local UI state and StoreKit Testing instead.
        //
        // `#else` rather than an early `return`, which made every line after it
        // unreachable on a simulator build and so warned on every such build,
        // burying anything else the compiler had to say.
        #if targetEnvironment(simulator)
        #if DEBUG
        // The one simulator path allowed to configure RevenueCat, and only ever
        // with the Test Store key: a separate RevenueCat app inside the same
        // project, so a probe run cannot touch App Store customers, revenue or
        // charts. See RevenueCatProbe.
        if RevenueCatProbe.isEnabled {
            Purchases.logLevel = .debug
            Purchases.configure(
                with: Configuration.Builder(withAPIKey: RevenueCatProbe.testStoreKey)
                    .with(appUserID: RevenueCatProbe.appUserID)
                    .build()
            )
            isConfigured = true
        }
        #endif
        #else
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        isConfigured = true
        #endif
    }
}

#if DEBUG
/// Simulator-only proof path for the fleet-wide funnel attributes.
///
/// Under the normal rules the attributes cannot be verified on a simulator: the
/// production key must never be configured there, so RevenueCat is never
/// configured, so nothing is ever sent, so a physical device is the only
/// witness. The Test Store key is a different RevenueCat app inside the same
/// project, so a probe run cannot touch App Store customers, revenue or charts.
///
/// DEBUG only, and only with the launch argument, so it cannot reach a Release
/// build or an ordinary simulator run.
enum RevenueCatProbe {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-rcfunnelprobe")
    }

    static let testStoreKey = "test_YdfGaRElhIbZeQWNtLhAznkKwAj"

    static var appUserID: String {
        ProcessInfo.processInfo.environment["RC_PROBE_USER"] ?? "funnel-probe-elderhub"
    }

    static var impressionID: String {
        ProcessInfo.processInfo.environment["RC_PROBE_SURFACE"] ?? "elderhub_paywall"
    }
}
#endif
