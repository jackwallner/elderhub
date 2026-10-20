package com.jackwallner.aging.model

import java.time.Instant
import java.time.LocalDate
import java.time.Period
import java.time.ZoneId
import java.util.UUID

/**
 * Port of `Shared/Models/CareModels.swift`. Enums are stored as raw strings on
 * iOS so the SwiftData migrations stay cheap; here they are Kotlin enums with
 * the same raw values, so a future sync speaks the same column values.
 *
 * Rows are immutable values held in one [CareState]. Child rows carry their
 * parent's id rather than an object reference.
 */
data class Person(
    val id: UUID = UUID.randomUUID(),
    val name: String = "",
    val relationship: String = "",
    val birthDate: LocalDate? = null,
    val bloodType: String = "",
    val isSelf: Boolean = false,
    val allergies: List<String> = emptyList(),
    val conditions: List<String> = emptyList(),
    val notes: String = "",
    /** When the supporter confirmed they may keep this person's information. */
    val surrogateAttestedAt: Instant? = null,
    val createdAt: Instant = Instant.now(),
) {
    /** The name they were entered under, everywhere. The relationship is the subtitle. */
    val displayLabel: String
        get() {
            val trimmed = name.trim()
            if (trimmed.isNotEmpty()) return trimmed
            return relationship.ifEmpty { "This person" }
        }

    fun age(today: LocalDate = LocalDate.now()): Int? = birthDate?.let { Period.between(it, today).years }
}

enum class MedicationForm(val raw: String) {
    TABLET("tablet"), CAPSULE("capsule"), LIQUID("liquid"), INJECTION("injection"), INHALER("inhaler"),
    PATCH("patch"), CREAM("cream"), DROPS("drops"), OTHER("other");

    val label: String get() = raw.replaceFirstChar(Char::uppercaseChar)

    companion object {
        fun of(raw: String?): MedicationForm = entries.firstOrNull { it.raw == raw } ?: OTHER
    }
}

data class Medication(
    val id: UUID = UUID.randomUUID(),
    val personId: UUID,
    val name: String = "",
    val strength: String = "",
    val form: MedicationForm = MedicationForm.TABLET,
    val purpose: String = "",
    val prescriber: String = "",
    val pharmacy: String = "",
    val instructions: String = "",
    /** Minutes from midnight, so a dose time survives a time-zone change. */
    val scheduleMinutes: List<Int> = emptyList(),
    /** Calendar's 1-indexed, Sunday-first numbering. Empty means every day. */
    val weekdays: List<Int> = emptyList(),
    val isAsNeeded: Boolean = false,
    val isActive: Boolean = true,
    val startDate: Instant = Instant.now(),
    val endDate: Instant? = null,
    val tracksRefills: Boolean = false,
    val quantityRemaining: Double = 0.0,
    val unitsPerDose: Double = 1.0,
    val refillThresholdDays: Int = 7,
    val providerId: UUID? = null,
    val pharmacyId: UUID? = null,
    val createdAt: Instant = Instant.now(),
) {
    /** "Lisinopril 10 mg": the line that goes on a printed list. */
    val displayName: String get() = if (strength.isEmpty()) name else "$name $strength"

    /** "Mon, Wed, Fri · 8:00 AM, 8:00 PM". Empty for as-needed or no times yet. */
    fun scheduleLabel(): String {
        if (isAsNeeded || scheduleMinutes.isEmpty()) return ""
        val times = scheduleMinutes.sorted().joinToString(", ") { ScheduleEngine.timeLabel(it) }
        val days = ScheduleEngine.weekdayLabel(weekdays)
        return if (days.isEmpty()) times else "$days · $times"
    }

    fun stopped(on: Instant = Instant.now()) = copy(isActive = false, endDate = on)

    fun restarted() = copy(isActive = true, endDate = null)

    fun isScheduled(on: Instant, zone: ZoneId): Boolean {
        if (!isActive || isAsNeeded) return false
        val startOfStart = startDate.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
        if (on < startOfStart) return false
        if (endDate != null && on > endDate) return false
        if (weekdays.isEmpty()) return true
        return ScheduleEngine.weekdayNumber(on.atZone(zone).toLocalDate()) in weekdays
    }

    /** Concrete dose times for the day containing [on], in order. */
    fun doseTimes(on: Instant, zone: ZoneId): List<Instant> {
        if (!isScheduled(on, zone)) return emptyList()
        val startOfDay = on.atZone(zone).toLocalDate().atStartOfDay(zone)
        return scheduleMinutes.sorted().map { startOfDay.plusMinutes(it.toLong()).toInstant() }
    }

    private val dosesPerDay: Double
        get() {
            if (scheduleMinutes.isEmpty()) return 0.0
            val timesPerDay = scheduleMinutes.size.toDouble()
            if (weekdays.isEmpty()) return timesPerDay
            return timesPerDay * weekdays.size / 7
        }

    /** Days the supply lasts. Null when untracked, as-needed or untimed; zero once empty. */
    val daysRemaining: Double?
        get() {
            if (isAsNeeded || !tracksRefills || unitsPerDose <= 0) return null
            val perDay = dosesPerDay
            if (perDay <= 0) return null
            return maxOf(0.0, quantityRemaining) / unitsPerDose / perDay
        }

    val isOutOfStock: Boolean get() = tracksRefills && quantityRemaining <= 0

    fun decrementedForDoseTaken(): Medication =
        if (!tracksRefills) this else copy(quantityRemaining = maxOf(0.0, quantityRemaining - unitsPerDose))

    fun restoredForDoseUntaken(): Medication =
        if (!tracksRefills) this else copy(quantityRemaining = maxOf(0.0, quantityRemaining) + unitsPerDose)
}

enum class DoseStatus(val raw: String, val label: String) {
    TAKEN("taken", "Taken"), SKIPPED("skipped", "Skipped"), MISSED("missed", "Missed");

    companion object {
        fun of(raw: String?): DoseStatus = entries.firstOrNull { it.raw == raw } ?: TAKEN
    }
}

/** Who dealt with a dose. The id is derived from (medication, minute) like iOS. */
data class DoseLog(
    val id: UUID,
    val medicationId: UUID,
    val scheduledAt: Instant,
    val status: DoseStatus = DoseStatus.TAKEN,
    val recordedBy: String = "",
    val recordedAt: Instant = Instant.now(),
    val note: String = "",
) {
    companion object {
        /** Fixed for the life of the app. Changing it would split a family's history in two. */
        val NAMESPACE: UUID = UUID.fromString("6f1d5b3e-6a5e-4a2c-9f0b-2f7a1c9d4e88")

        fun deterministicId(medicationId: UUID, scheduledAt: Instant): UUID {
            val minute = Math.floorDiv(scheduledAt.epochSecond, 60L)
            return DeterministicId.v5(NAMESPACE, "${medicationId.toString().lowercase()}:$minute")
        }

        fun create(medicationId: UUID, scheduledAt: Instant, status: DoseStatus, recordedBy: String, now: Instant = Instant.now()) =
            DoseLog(deterministicId(medicationId, scheduledAt), medicationId, scheduledAt, status, recordedBy, now)
    }
}

data class Visit(
    val id: UUID = UUID.randomUUID(),
    val personId: UUID,
    val date: Instant,
    val provider: String = "",
    val specialty: String = "",
    val reason: String = "",
    val notes: String = "",
    val followUp: String = "",
    val createdAt: Instant = Instant.now(),
) {
    /** A visit dated later than now is an appointment nobody has been to yet. */
    fun isUpcoming(now: Instant = Instant.now()) = date > now

    /** Only something still to come has a time anybody chose; midnight means date only. */
    fun hasTimeOfDay(zone: ZoneId, now: Instant = Instant.now()): Boolean {
        if (!isUpcoming(now)) return false
        val local = date.atZone(zone)
        return local.hour != 0 || local.minute != 0
    }

    fun displayTitle(): String = listOf(provider, specialty, reason).firstOrNull { it.isNotEmpty() } ?: "Appointment"
}

data class EmergencyContact(
    val id: UUID = UUID.randomUUID(),
    val personId: UUID,
    val name: String = "",
    val relationship: String = "",
    val phone: String = "",
    val isPrimary: Boolean = false,
)

data class Provider(
    val id: UUID = UUID.randomUUID(),
    val personId: UUID,
    val name: String = "",
    val specialty: String = "",
    val phone: String = "",
    val address: String = "",
    val notes: String = "",
    val isPharmacy: Boolean = false,
)

/** Everything on this phone. One immutable value, saved whole. */
data class CareState(
    val people: List<Person> = emptyList(),
    val medications: List<Medication> = emptyList(),
    val doses: List<DoseLog> = emptyList(),
    val visits: List<Visit> = emptyList(),
    val contacts: List<EmergencyContact> = emptyList(),
    val providers: List<Provider> = emptyList(),
    val caregiverName: String = "",
    val hasCompletedOnboarding: Boolean = false,
) {
    fun person(id: UUID): Person? = people.firstOrNull { it.id == id }

    fun medicationsOf(personId: UUID) = medications.filter { it.personId == personId }

    fun activeMedications(personId: UUID) = medicationsOf(personId).filter { it.isActive }.sortedBy { it.name }

    fun stoppedMedications(personId: UUID) = medicationsOf(personId).filter { !it.isActive }.sortedBy { it.name }

    fun dosesOf(medicationId: UUID) = doses.filter { it.medicationId == medicationId }

    fun visitsOf(personId: UUID) = visits.filter { it.personId == personId }

    fun upcomingVisits(personId: UUID, now: Instant = Instant.now()) =
        visitsOf(personId).filter { it.isUpcoming(now) }.sortedBy { it.date }

    /** A week out, no further: what Today shows. */
    fun appointmentsDue(personId: UUID, now: Instant = Instant.now(), withinDays: Long = 7) =
        upcomingVisits(personId, now).filter { it.date <= now.plus(java.time.Duration.ofDays(withinDays)) }

    /** Tracked medications at or under their refill threshold, emptiest first (`TodayDigest.runningLow`). */
    fun runningLow(personId: UUID): List<Medication> =
        activeMedications(personId)
            .filter { med -> med.daysRemaining?.let { it <= med.refillThresholdDays } ?: false }
            .sortedBy { it.daysRemaining ?: 0.0 }

    fun pastVisits(personId: UUID, now: Instant = Instant.now()) =
        visitsOf(personId).filter { !it.isUpcoming(now) }.sortedByDescending { it.date }

    /** Primary first, then alphabetical: the order the card and the export print. */
    fun contactsOf(personId: UUID) =
        contacts.filter { it.personId == personId }.sortedWith(compareBy<EmergencyContact>({ !it.isPrimary }, { it.name }))

    fun providersOf(personId: UUID) = providers.filter { it.personId == personId }.sortedBy { it.name }

    fun provider(id: UUID?): Provider? = id?.let { pid -> providers.firstOrNull { it.id == pid } }
}
