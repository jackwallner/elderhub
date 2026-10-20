package com.jackwallner.aging.data

import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.text.NumberFormat
import java.util.Currency

/**
 * Every string the paywall shows, as pure functions of the selected plan and
 * the trial this account would get. Ports the computed properties of
 * `PaywallView.swift`; the Apple ID wording becomes Google Play's.
 */
object PaywallCopy {
    val BENEFITS = listOf(
        "Keep care records for Mom, Dad, a partner, or anyone else",
        "One Today screen that answers for everyone, not one person at a time",
        "Every care feature is included for every person",
    )

    private const val RENEWAL =
        "Cancel at least 24 hours before the period ends to avoid renewal. Manage or cancel in Google Play › Payments & subscriptions."

    /** Cheapest commitment first, whatever order the store returned. */
    fun ordered(plans: List<Plan>): List<Plan> {
        val rank = listOf(PackageKind.MONTHLY, PackageKind.YEARLY, PackageKind.LIFETIME, PackageKind.OTHER)
        return plans.sortedBy { rank.indexOf(it.kind) }
    }

    /** Yearly is preselected, like iOS: it is the plan most families keep. */
    fun defaultSelection(plans: List<Plan>): Plan? =
        plans.firstOrNull { it.kind == PackageKind.YEARLY } ?: plans.firstOrNull()

    fun headline(trialDays: Int?): String = trialDays?.let { "Free for $it days" } ?: "Add another person"

    fun subhead(trialDays: Int?): String =
        if (trialDays == null) "Care records for everyone you look after, in one circle."
        else "Add everyone you look after. Full access from today, nothing to pay now."

    fun cta(plan: Plan?, trialDays: Int?, isPurchasing: Boolean): String = when {
        plan == null -> "Continue"
        isPurchasing -> "Working…"
        trialDays != null -> "Start My $trialDays-Day Free Trial"
        plan.kind == PackageKind.LIFETIME -> "Unlock Lifetime"
        else -> "Subscribe"
    }

    fun planTitle(plan: Plan): String = when (plan.kind) {
        PackageKind.MONTHLY -> "Monthly"
        PackageKind.YEARLY -> "Yearly"
        PackageKind.LIFETIME -> "Lifetime"
        PackageKind.OTHER -> plan.title.ifEmpty { "Elderhub Plus" }
    }

    /** The line under each plan's title. Lifetime never carries trial or subscription words. */
    fun planDetail(plan: Plan, trialDays: Int?): String {
        val prefix = trialDays?.let { "$it days free, then " } ?: ""
        return when (plan.kind) {
            PackageKind.MONTHLY -> if (prefix.isEmpty()) "Cancel any time" else "$prefix${plan.priceFormatted} a month"
            PackageKind.YEARLY -> {
                val perMonth = perMonthLabel(plan)
                when {
                    perMonth != null -> "$prefix$perMonth a month, billed yearly"
                    prefix.isEmpty() -> "Billed yearly"
                    else -> "$prefix${plan.priceFormatted} a year"
                }
            }
            PackageKind.LIFETIME -> "One payment, no renewal"
            PackageKind.OTHER -> plan.priceLabel
        }
    }

    /** "$4.08" for a yearly plan. Null for anything under two months. */
    fun perMonthLabel(plan: Plan): String? {
        val months = plan.monthsInPeriod ?: return null
        if (months < BigDecimal(2) || plan.priceMicros <= 0) return null
        val perMonth = plan.price.divide(months, MathContext.DECIMAL64).setScale(2, RoundingMode.HALF_EVEN)
        return NumberFormat.getCurrencyInstance().apply {
            runCatching { currency = Currency.getInstance(plan.currencyCode) }
            minimumFractionDigits = 2
            maximumFractionDigits = 2
        }.format(perMonth)
    }

    /** Whole per cent saved against twelve months of monthly, rounded down; null unless real. */
    fun savingsPercent(yearly: Plan, monthly: Plan?): Int? {
        if (yearly.kind != PackageKind.YEARLY || monthly == null || monthly.kind != PackageKind.MONTHLY) return null
        if (monthly.priceMicros <= 0) return null
        val twelve = monthly.priceMicros * 12
        if (yearly.priceMicros >= twelve) return null
        val percent = ((twelve - yearly.priceMicros) * 100 / twelve).toInt()
        return percent.takeIf { it > 0 }
    }

    /** The required disclosure, rebuilt for the selected plan. */
    fun disclosure(plan: Plan?, trialDays: Int?): String? {
        plan ?: return null
        if (plan.kind == PackageKind.LIFETIME) return "${plan.priceFormatted} once. Lifetime access, no subscription and no renewal."
        val unit = if (plan.kind == PackageKind.YEARLY) "year" else "month"
        if (trialDays != null) return "Free for $trialDays days, then ${plan.priceFormatted} per $unit, renewing automatically. $RENEWAL"
        return "${plan.priceFormatted} per $unit, renewing automatically. $RENEWAL"
    }
}
