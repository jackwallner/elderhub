package com.jackwallner.aging.model

import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.UUID

/**
 * One reminder per person per dose time (and weekday), not per medication, as
 * in `DoseReminderScheduler.swift`: adding a tablet to the 8am slot rewrites
 * the 8am reminder instead of adding another.
 */
data class ReminderSpec(
    val personId: UUID,
    val personName: String,
    val medicationNames: List<String>,
    val hour: Int,
    val minute: Int,
    /** Calendar numbering, 1 = Sunday; null is every day. */
    val weekday: Int?,
) {
    val identifier: String get() = "$PREFIX${personId.toString().uppercase()}-${hour * 60 + minute}-${weekday ?: 0}"

    val title: String get() = if (medicationNames.size > 1) "Time for ${medicationNames.size} doses" else "Time for a dose"

    val body: String
        get() {
            val listed = when (medicationNames.size) {
                0 -> "a dose is due"
                1 -> medicationNames[0]
                2 -> "${medicationNames[0]} and ${medicationNames[1]}"
                else -> "${medicationNames[0]}, ${medicationNames[1]} and ${medicationNames.size - 2} more"
            }
            return if (personName.isEmpty()) listed else "$personName: $listed"
        }

    /** The next moment strictly after [after] this reminder fires, in [zone]'s wall clock. */
    fun nextFire(after: Instant, zone: ZoneId): Instant {
        val start = after.atZone(zone)
        var candidate: ZonedDateTime = start.toLocalDate().atTime(hour, minute).atZone(zone)
        repeat(8) {
            val dayOk = weekday == null || ScheduleEngine.weekdayNumber(candidate.toLocalDate()) == weekday
            if (dayOk && candidate.toInstant() > after) return candidate.toInstant()
            candidate = candidate.toLocalDate().plusDays(1).atTime(hour, minute).atZone(zone)
        }
        return candidate.toInstant()
    }

    companion object {
        const val PREFIX = "dose-"
    }
}

object DoseReminderPlanner {

    fun plan(state: CareState, enabledPeople: Set<UUID>, now: Instant = Instant.now()): List<ReminderSpec> {
        val grouped = linkedMapOf<Triple<UUID, Int, Int?>, MutableSet<String>>()
        for (person in state.people.filter { it.id in enabledPeople }) {
            for (med in state.medicationsOf(person.id).filter { eligible(it, now) }) {
                val days: List<Int?> = if (med.weekdays.isEmpty()) listOf(null) else med.weekdays.sorted()
                for (minutes in med.scheduleMinutes.sorted()) {
                    for (day in days) grouped.getOrPut(Triple(person.id, minutes, day)) { mutableSetOf() } += med.displayName
                }
            }
        }
        return grouped.map { (key, names) ->
            val person = state.person(key.first)
            ReminderSpec(key.first, person?.displayLabel.orEmpty(), names.sorted(), key.second / 60, key.second % 60, key.third)
        }.sortedBy { it.identifier }
    }

    /** The soonest fire time across every spec, and the specs that fire then. */
    fun next(specs: List<ReminderSpec>, after: Instant, zone: ZoneId): Pair<Instant, List<ReminderSpec>>? {
        if (specs.isEmpty()) return null
        val times = specs.map { it to it.nextFire(after, zone) }
        val soonest = times.minOf { it.second }
        return soonest to times.filter { it.second == soonest }.map { it.first }
    }

    /** Every reminder whose next time after [after] falls on or before [until]. */
    fun due(specs: List<ReminderSpec>, after: Instant, until: Instant, zone: ZoneId): List<ReminderSpec> =
        specs.filter { it.nextFire(after, zone) <= until }

    private fun eligible(med: Medication, now: Instant): Boolean {
        if (!med.isActive || med.isAsNeeded || med.scheduleMinutes.isEmpty()) return false
        val end = med.endDate
        return end == null || end >= now
    }
}
