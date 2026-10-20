package com.jackwallner.aging.data

import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.text.NumberFormat
import java.util.Currency

enum class PackageKind {
    YEARLY, MONTHLY, LIFETIME, OTHER;

    companion object {
        fun fromIdentifiers(vararg ids: String): PackageKind {
            val lower = ids.map { it.lowercase() }
            return when {
                lower.any { "lifetime" in it } -> LIFETIME
                lower.any { "yearly" in it || "annual" in it } -> YEARLY
                lower.any { "monthly" in it } -> MONTHLY
                else -> OTHER
            }
        }
    }
}

enum class PeriodUnit { DAY, WEEK, MONTH, YEAR }

data class PlanPeriod(val value: Int, val unit: PeriodUnit) {
    /** Trial length in days, the way the iOS label reads it. */
    val days: Int
        get() = when (unit) {
            PeriodUnit.DAY -> value
            PeriodUnit.WEEK -> value * 7
            PeriodUnit.MONTH -> value * 30
            PeriodUnit.YEAR -> value * 365
        }
}

/**
 * A purchasable plan, detached from the RevenueCat SDK so every price string
 * the paywall shows is a pure function of what the store returned. Ports the
 * `Package` extensions in `SubscriptionPackageExtensions.swift`.
 */
data class Plan(
    val packageId: String,
    val productId: String,
    val kind: PackageKind,
    val priceMicros: Long,
    val priceFormatted: String,
    val currencyCode: String,
    val period: PlanPeriod?,
    val trial: PlanPeriod?,
    val title: String = "",
) {
    val price: BigDecimal get() = BigDecimal.valueOf(priceMicros, 6)

    val displayName: String
        get() = when (kind) {
            PackageKind.LIFETIME -> "Lifetime"
            PackageKind.YEARLY -> "Yearly"
            PackageKind.MONTHLY -> "Monthly"
            PackageKind.OTHER -> title
        }

    /** "$9.99 / month", or the bare price for a one-time product. */
    val priceLabel: String
        get() {
            val p = period ?: return priceFormatted
            val unit = unitName(p.unit, p.value)
            return if (p.value == 1) "$priceFormatted / $unit" else "$priceFormatted / ${p.value} $unit"
        }

    val monthsInPeriod: BigDecimal?
        get() {
            val p = period ?: return null
            val v = BigDecimal(p.value)
            return when (p.unit) {
                PeriodUnit.DAY -> v.divide(BigDecimal(30), MathContext.DECIMAL64)
                PeriodUnit.WEEK -> v.divide(BigDecimal("4.345"), MathContext.DECIMAL64)
                PeriodUnit.MONTH -> v
                PeriodUnit.YEAR -> v.multiply(BigDecimal(12))
            }
        }

    /** "$2.50 / mo" for plans of two months or more. */
    val perMonthLabel: String?
        get() {
            val months = monthsInPeriod ?: return null
            if (months < BigDecimal(2)) return null
            return "${currency(price.divide(months, MathContext.DECIMAL64))} / mo"
        }

    fun savingsPercent(monthly: Plan?): Int? {
        monthly ?: return null
        val months = monthsInPeriod ?: return null
        if (months < BigDecimal(2)) return null
        val projected = monthly.price.multiply(months).toDouble()
        val actual = price.toDouble()
        if (projected <= 0 || actual <= 0) return null
        val saved = projected - actual
        if (saved <= 0) return null
        return Math.round(saved / projected * 100).toInt()
    }

    /** The strikethrough monthly-times-twelve anchor. */
    fun anchorPriceLabel(monthly: Plan?): String? {
        monthly ?: return null
        val months = monthsInPeriod ?: return null
        if (months < BigDecimal(2)) return null
        val projected = monthly.price.multiply(months)
        if (projected <= price) return null
        return currency(projected)
    }

    /** "7-day free trial" when the plan carries a free-trial offer. */
    val introOfferLabel: String?
        get() {
            val t = trial ?: return null
            if (t.unit == PeriodUnit.WEEK) return "${t.value * 7}-day free trial"
            val unit = unitName(t.unit, t.value)
            return "${t.value}-${if (t.value == 1) unit else unit.dropLast(1)} free trial"
        }

    private fun currency(amount: BigDecimal): String {
        val format = NumberFormat.getCurrencyInstance().apply {
            runCatching { currency = Currency.getInstance(currencyCode) }
            minimumFractionDigits = 2
            maximumFractionDigits = 2
        }
        return format.format(amount.setScale(2, RoundingMode.HALF_EVEN))
    }

    private fun unitName(unit: PeriodUnit, value: Int): String = when (unit) {
        PeriodUnit.DAY -> if (value == 1) "day" else "days"
        PeriodUnit.WEEK -> if (value == 1) "week" else "weeks"
        PeriodUnit.MONTH -> if (value == 1) "month" else "months"
        PeriodUnit.YEAR -> if (value == 1) "year" else "years"
    }
}
