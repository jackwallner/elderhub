import Foundation
import Testing

@testable import Aging

/// The paywall's two numeric claims: how much the yearly plan saves, and how
/// long the free trial runs. Both shipped broken in their own way — the savings
/// badge silently never rendered, and the trial was known only to the legal
/// paragraph — so both are pinned here rather than left to a screenshot.
struct PlanOptionTests {

    private func plan(
        _ id: String,
        _ amount: Decimal,
        _ period: PlanPeriod,
        trialDays: Int? = nil
    ) -> PlanOption {
        PlanOption(
            id: id,
            title: ProProduct.title(for: id),
            price: amount.formatted(.currency(code: "USD")),
            amount: amount,
            currencyCode: "USD",
            period: period,
            package: nil,
            trialDays: trialDays
        )
    }

    private var monthly: PlanOption { plan(ProProduct.monthly, 9.99, .monthly, trialDays: 7) }
    private var yearly: PlanOption { plan(ProProduct.yearly, 39.99, .yearly, trialDays: 7) }
    private var lifetime: PlanOption { plan(ProProduct.lifetime, 89.99, .lifetime) }

    /// The regression this file exists for. The old `Int(truncating:)` read 0
    /// out of a Decimal like 66.641641…, so the badge was dropped on every
    /// build and the yearly plan looked merely more expensive than the monthly.
    @Test func theYearlyPlanReportsItsRealSaving() {
        #expect(yearly.savingsPercent(against: monthly) == 66)
    }

    @Test func aLongFractionDoesNotCollapseToZero() {
        // 29.99 against 4.99 a month is 49.916…%, the other shape of the same bug.
        let cheapMonthly = plan(ProProduct.monthly, 4.99, .monthly)
        let cheapYearly = plan(ProProduct.yearly, 29.99, .yearly)
        #expect(cheapYearly.savingsPercent(against: cheapMonthly) == 49)
    }

    /// Rounded down, so the badge can never promise more than the prices do.
    @Test func theSavingIsRoundedDownRatherThanNearest() {
        let m = plan(ProProduct.monthly, 1.00, .monthly)
        let y = plan(ProProduct.yearly, 3.99, .yearly)   // 66.75% saved
        #expect(y.savingsPercent(against: m) == 66)
    }

    @Test func onlyTheYearlyPlanCarriesTheBadge() {
        #expect(monthly.savingsPercent(against: monthly) == nil)
        #expect(lifetime.savingsPercent(against: monthly) == nil)
    }

    @Test func thereIsNoBadgeWithoutAMonthlyPriceToCompareAgainst() {
        #expect(yearly.savingsPercent(against: nil) == nil)
    }

    /// A yearly plan priced at or above twelve months is not a saving, and the
    /// badge stays away rather than showing "Save 0%".
    @Test func aYearlyPlanThatSavesNothingGetsNoBadge() {
        let m = plan(ProProduct.monthly, 3.00, .monthly)
        let y = plan(ProProduct.yearly, 36.00, .yearly)
        #expect(y.savingsPercent(against: m) == nil)
    }

    /// A trial is only ever advertised in days, whatever unit the store states
    /// it in, so "1 week" and "7 days" cannot produce two different pitches.
    @Test func lifetimeNeverCarriesATrial() {
        #expect(lifetime.trialDays == nil)
    }
}
