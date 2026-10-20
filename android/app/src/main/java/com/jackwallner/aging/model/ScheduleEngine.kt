package com.jackwallner.aging.model

import java.security.MessageDigest
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.time.temporal.WeekFields
import java.util.Locale
import java.util.UUID

/** One scheduled dose on a given day, resolved against what has been logged. */
data class DoseSlot(
    val id: String,
    val personId: UUID,
    val medicationId: UUID,
    val medicationName: String,
    val strength: String,
    val scheduledAt: Instant,
    val status: DoseStatus?,
    val recordedBy: String,
) {
    val isPending: Boolean get() = status == null
}

/** Port of `ScheduleEngine.swift`: pure functions over the care state. */
object ScheduleEngine {

    fun slots(state: CareState, personId: UUID, on: Instant, zone: ZoneId): List<DoseSlot> {
        val result = mutableListOf<DoseSlot>()
        for (medication in state.activeMedications(personId)) {
            val logs = state.dosesOf(medication.id)
            for (time in medication.doseTimes(on, zone)) {
                val minute = time.truncatedTo(ChronoUnit.MINUTES)
                val log = logs.firstOrNull { it.scheduledAt.truncatedTo(ChronoUnit.MINUTES) == minute }
                result += DoseSlot(
                    id = "${medication.id}-${time.epochSecond}",
                    personId = personId,
                    medicationId = medication.id,
                    medicationName = medication.name,
                    strength = medication.strength,
                    scheduledAt = time,
                    status = log?.status,
                    recordedBy = log?.recordedBy ?: "",
                )
            }
        }
        return result.sortedBy { it.scheduledAt }
    }

    fun overdueSlots(state: CareState, personId: UUID, on: Instant, now: Instant, zone: ZoneId): List<DoseSlot> =
        slots(state, personId, on, zone).filter { it.isPending && it.scheduledAt < now }

    /** Share of scheduled doses marked taken over a window ending on [endingOn]. */
    fun adherence(state: CareState, personId: UUID, days: Int, endingOn: Instant, zone: ZoneId): Double? {
        if (days <= 0) return null
        var scheduled = 0
        var taken = 0
        val end = endingOn.atZone(zone)
        for (offset in 0 until days) {
            val day = end.minusDays(offset.toLong()).toInstant()
            for (slot in slots(state, personId, day, zone)) {
                scheduled += 1
                if (slot.status == DoseStatus.TAKEN) taken += 1
            }
        }
        if (scheduled == 0) return null
        return taken.toDouble() / scheduled
    }

    fun timeLabel(minutes: Int, locale: Locale = Locale.getDefault()): String =
        LocalTime.MIDNIGHT.plusMinutes(minutes.toLong())
            .format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale))

    /** "" for every day, "Mondays" for one day, "Mon, Wed, Fri" otherwise. */
    fun weekdayLabel(weekdays: List<Int>, locale: Locale = Locale.getDefault()): String {
        val days = weekdays.filter { it in 1..7 }.toSet()
        if (days.isEmpty() || days.size >= 7) return ""
        val ordered = orderedWeekdays(locale).filter { it in days }
        if (ordered.size == 1) return "${dayOfWeek(ordered[0]).getDisplayName(TextStyle.FULL, locale)}s"
        return ordered.joinToString(", ") { dayOfWeek(it).getDisplayName(TextStyle.SHORT, locale) }
    }

    /** 1...7 starting at the locale's first weekday, so a Monday-first locale reads in order. */
    fun orderedWeekdays(locale: Locale = Locale.getDefault()): List<Int> {
        val first = weekdayNumber(WeekFields.of(locale).firstDayOfWeek)
        return (0 until 7).map { ((first - 1 + it) % 7) + 1 }
    }

    /** Calendar's 1 = Sunday ... 7 = Saturday. */
    fun weekdayNumber(date: LocalDate): Int = weekdayNumber(date.dayOfWeek)

    fun weekdayNumber(day: DayOfWeek): Int = day.value % 7 + 1

    fun dayOfWeek(number: Int): DayOfWeek = DayOfWeek.of((number + 5) % 7 + 1)

    fun minutes(of: Instant, zone: ZoneId): Int {
        val time = of.atZone(zone)
        return time.hour * 60 + time.minute
    }
}

/** RFC 4122 version 5 UUIDs, byte-identical to `DeterministicID.v5` on iOS. */
object DeterministicId {
    fun v5(namespace: UUID, name: String): UUID {
        val bytes = java.nio.ByteBuffer.allocate(16)
            .putLong(namespace.mostSignificantBits)
            .putLong(namespace.leastSignificantBits)
            .array()
        val sha = MessageDigest.getInstance("SHA-1")
        sha.update(bytes)
        sha.update(name.toByteArray(Charsets.UTF_8))
        val digest = sha.digest().copyOf(16)
        digest[6] = ((digest[6].toInt() and 0x0F) or 0x50).toByte()
        digest[8] = ((digest[8].toInt() and 0x3F) or 0x80).toByte()
        val buffer = java.nio.ByteBuffer.wrap(digest)
        return UUID(buffer.long, buffer.long)
    }
}
