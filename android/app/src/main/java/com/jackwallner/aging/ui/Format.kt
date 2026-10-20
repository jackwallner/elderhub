package com.jackwallner.aging.ui

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** Display formatting in the phone's zone and locale. */
object Format {
    val zone: ZoneId get() = ZoneId.systemDefault()

    fun time(instant: Instant): String =
        instant.atZone(zone).format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT))

    fun date(instant: Instant): String =
        instant.atZone(zone).format(DateTimeFormatter.ofPattern("EEE d MMM"))

    fun date(date: LocalDate): String = date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))

    /** "Tue 24 Sep" or "Tue 24 Sep at 9:30 AM" when a time was chosen. */
    fun visitDate(instant: Instant, hasTime: Boolean): String =
        if (hasTime) "${date(instant)} at ${time(instant)}" else date(instant)

    fun daysLeft(daysRemaining: Double?, outOfStock: Boolean): String {
        if (outOfStock) return "None left"
        val days = daysRemaining?.let { maxOf(0, Math.round(it).toInt()) } ?: return "Refill soon"
        if (days == 0) return "Last dose today"
        return if (days == 1) "1 day left" else "$days days left"
    }
}
