package com.jackwallner.aging

import com.jackwallner.aging.data.InMemoryStore
import com.jackwallner.aging.data.PackageKind
import com.jackwallner.aging.data.PaywallCopy
import com.jackwallner.aging.data.PeriodUnit
import com.jackwallner.aging.data.Plan
import com.jackwallner.aging.data.PlanPeriod
import com.jackwallner.aging.data.ProProduct
import com.jackwallner.aging.data.ReviewAccess
import java.security.MessageDigest
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/** The paywall's words, from `PaywallView.swift`, as pure functions of plan and trial. */
class PaywallCopyTest {
    private val week = PlanPeriod(1, PeriodUnit.WEEK)
    private val monthly = Plan("\$rc_monthly", ProProduct.MONTHLY, PackageKind.MONTHLY, 9_990_000, "$9.99", "USD", PlanPeriod(1, PeriodUnit.MONTH), week)
    private val yearly = Plan("\$rc_annual", ProProduct.YEARLY, PackageKind.YEARLY, 39_990_000, "$39.99", "USD", PlanPeriod(1, PeriodUnit.YEAR), week)
    private val lifetime = Plan("\$rc_lifetime", ProProduct.LIFETIME, PackageKind.LIFETIME, 89_990_000, "$89.99", "USD", null, null)

    @Before fun locale() = Locale.setDefault(Locale.US)

    @Test fun plansReadCheapestCommitmentFirstAndYearlyIsPreselected() {
        val ordered = PaywallCopy.ordered(listOf(lifetime, yearly, monthly))
        assertEquals(listOf(PackageKind.MONTHLY, PackageKind.YEARLY, PackageKind.LIFETIME), ordered.map { it.kind })
        assertEquals(yearly, PaywallCopy.defaultSelection(ordered))
        assertEquals(lifetime, PaywallCopy.defaultSelection(listOf(lifetime)))
        assertNull(PaywallCopy.defaultSelection(emptyList()))
    }

    @Test fun headlineAndCtaFollowTheTrialThisAccountWouldGet() {
        assertEquals("Add another person", PaywallCopy.headline(null))
        assertEquals("Free for 7 days", PaywallCopy.headline(7))
        assertEquals("Start My 7-Day Free Trial", PaywallCopy.cta(yearly, 7, false))
        assertEquals("Subscribe", PaywallCopy.cta(yearly, null, false))
        assertEquals("Unlock Lifetime", PaywallCopy.cta(lifetime, null, false))
        assertEquals("Working…", PaywallCopy.cta(yearly, 7, true))
        assertEquals("Continue", PaywallCopy.cta(null, null, false))
    }

    @Test fun yearlyShowsItsMonthlyEquivalentAndAnHonestSaving() {
        assertEquals("$3.33 a month, billed yearly", PaywallCopy.planDetail(yearly, null))
        assertEquals("7 days free, then $3.33 a month, billed yearly", PaywallCopy.planDetail(yearly, 7))
        // 12 x 9.99 = 119.88; 39.99 saves 66.64%, rounded down like iOS.
        assertEquals(66, PaywallCopy.savingsPercent(yearly, monthly))
        assertNull(PaywallCopy.savingsPercent(monthly, monthly))
        assertNull(PaywallCopy.savingsPercent(yearly.copy(priceMicros = 200_000_000), monthly))
    }

    @Test fun lifetimeNeverCarriesTrialOrRenewalWords() {
        assertEquals("One payment, no renewal", PaywallCopy.planDetail(lifetime, 7))
        val disclosure = PaywallCopy.disclosure(lifetime, null)!!
        assertEquals("$89.99 once. Lifetime access, no subscription and no renewal.", disclosure)
        assertFalse(disclosure.contains("renewing automatically"))
    }

    @Test fun subscriptionDisclosureNamesPriceTermTrialAndHowToCancel() {
        val trial = PaywallCopy.disclosure(monthly, 7)!!
        assertTrue(trial.startsWith("Free for 7 days, then $9.99 per month, renewing automatically."))
        assertTrue(trial.contains("Google Play › Payments & subscriptions"))
        assertFalse(trial.contains("Apple"))
        assertTrue(PaywallCopy.disclosure(yearly, null)!!.startsWith("$39.99 per year, renewing automatically."))
        assertEquals("Cancel any time", PaywallCopy.planDetail(monthly, null))
        assertEquals("7 days free, then $9.99 a month", PaywallCopy.planDetail(monthly, 7))
    }

    @Test fun theBenefitsAreThingsThisPurchaseBuys() {
        assertEquals(3, PaywallCopy.BENEFITS.size)
        assertFalse(PaywallCopy.BENEFITS.any { it.contains("seat", ignoreCase = true) })
    }
}

/** The entitlement and reviewer access that gate the second person. */
class EntitlementTest {
    @Test fun agingPlusAndItsLegacyAliasesUnlock() {
        assertTrue(ProProduct.isEntitled(setOf("Aging+")))
        assertTrue(ProProduct.isEntitled(setOf("pro")))
        assertTrue(ProProduct.isEntitled(setOf("AgingPro")))
        assertFalse(ProProduct.isEntitled(emptySet()))
        assertFalse(ProProduct.isEntitled(setOf("bloom")))
    }

    @Test fun productIdsMatchIos() {
        assertEquals(
            listOf("com.jackwallner.aging.pro.monthly", "com.jackwallner.aging.pro.yearly", "com.jackwallner.aging.pro.lifetime"),
            ProProduct.all,
        )
    }

    @Test fun reviewerAccessNeedsTheExactCode() {
        val digest = MessageDigest.getInstance("SHA-256").digest("review-code-123".toByteArray()).joinToString("") { "%02x".format(it) }
        val defaults = InMemoryStore()
        val access = ReviewAccess(defaults, digest)
        assertFalse(access.isGranted)
        assertFalse(access.activate("wrong"))
        assertFalse(access.isGranted)
        assertTrue(access.activate(" review-code-123 "))
        assertTrue(ReviewAccess(defaults, digest).isGranted)
        // A build without a configured digest never grants access.
        assertFalse(ReviewAccess(InMemoryStore(), "").activate("review-code-123"))
    }
}
