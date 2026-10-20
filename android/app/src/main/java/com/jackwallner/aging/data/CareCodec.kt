package com.jackwallner.aging.data

import com.jackwallner.aging.model.CareState
import com.jackwallner.aging.model.DoseLog
import com.jackwallner.aging.model.DoseStatus
import com.jackwallner.aging.model.EmergencyContact
import com.jackwallner.aging.model.Medication
import com.jackwallner.aging.model.MedicationForm
import com.jackwallner.aging.model.Person
import com.jackwallner.aging.model.Provider
import com.jackwallner.aging.model.Visit
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/**
 * The on-phone file format. Field names follow the Supabase column names
 * (`schedule_minutes`, `recorded_by_name`) so a later sync maps one to one.
 * Unknown or missing fields fall back to defaults rather than failing the load:
 * a care record that will not open is worse than one missing a new field.
 */
object CareCodec {
    private const val VERSION = 1

    fun encode(state: CareState): String = JSONObject().apply {
        put("version", VERSION)
        put("caregiver_name", state.caregiverName)
        put("has_completed_onboarding", state.hasCompletedOnboarding)
        put("people", JSONArray(state.people.map(::person)))
        put("medications", JSONArray(state.medications.map(::medication)))
        put("dose_logs", JSONArray(state.doses.map(::dose)))
        put("visits", JSONArray(state.visits.map(::visit)))
        put("emergency_contacts", JSONArray(state.contacts.map(::contact)))
        put("providers", JSONArray(state.providers.map(::provider)))
    }.toString()

    fun decode(text: String): CareState {
        val root = JSONObject(text)
        return CareState(
            people = root.objects("people").mapNotNull { runCatching { person(it) }.getOrNull() },
            medications = root.objects("medications").mapNotNull { runCatching { medication(it) }.getOrNull() },
            doses = root.objects("dose_logs").mapNotNull { runCatching { dose(it) }.getOrNull() },
            visits = root.objects("visits").mapNotNull { runCatching { visit(it) }.getOrNull() },
            contacts = root.objects("emergency_contacts").mapNotNull { runCatching { contact(it) }.getOrNull() },
            providers = root.objects("providers").mapNotNull { runCatching { provider(it) }.getOrNull() },
            caregiverName = root.optString("caregiver_name"),
            hasCompletedOnboarding = root.optBoolean("has_completed_onboarding"),
        )
    }

    private fun person(p: Person) = JSONObject().apply {
        put("id", p.id.toString())
        put("name", p.name)
        put("relationship", p.relationship)
        p.birthDate?.let { put("birth_date", it.toString()) }
        put("blood_type", p.bloodType)
        put("is_self", p.isSelf)
        put("allergies", JSONArray(p.allergies))
        put("conditions", JSONArray(p.conditions))
        put("notes", p.notes)
        p.surrogateAttestedAt?.let { put("surrogate_attested_at", it.toString()) }
        put("created_at", p.createdAt.toString())
    }

    private fun person(o: JSONObject) = Person(
        id = UUID.fromString(o.getString("id")),
        name = o.optString("name"),
        relationship = o.optString("relationship"),
        birthDate = o.optStringOrNull("birth_date")?.let(LocalDate::parse),
        bloodType = o.optString("blood_type"),
        isSelf = o.optBoolean("is_self"),
        allergies = o.strings("allergies"),
        conditions = o.strings("conditions"),
        notes = o.optString("notes"),
        surrogateAttestedAt = o.instant("surrogate_attested_at"),
        createdAt = o.instant("created_at") ?: Instant.EPOCH,
    )

    private fun medication(m: Medication) = JSONObject().apply {
        put("id", m.id.toString())
        put("person_id", m.personId.toString())
        put("name", m.name)
        put("strength", m.strength)
        put("form", m.form.raw)
        put("purpose", m.purpose)
        put("prescriber", m.prescriber)
        put("pharmacy", m.pharmacy)
        put("instructions", m.instructions)
        put("schedule_minutes", JSONArray(m.scheduleMinutes))
        put("weekdays", JSONArray(m.weekdays))
        put("is_as_needed", m.isAsNeeded)
        put("is_active", m.isActive)
        put("start_date", m.startDate.toString())
        m.endDate?.let { put("end_date", it.toString()) }
        put("tracks_refills", m.tracksRefills)
        put("quantity_remaining", m.quantityRemaining)
        put("units_per_dose", m.unitsPerDose)
        put("refill_threshold_days", m.refillThresholdDays)
        m.providerId?.let { put("provider_id", it.toString()) }
        m.pharmacyId?.let { put("pharmacy_id", it.toString()) }
        put("created_at", m.createdAt.toString())
    }

    private fun medication(o: JSONObject) = Medication(
        id = UUID.fromString(o.getString("id")),
        personId = UUID.fromString(o.getString("person_id")),
        name = o.optString("name"),
        strength = o.optString("strength"),
        form = MedicationForm.of(o.optStringOrNull("form")),
        purpose = o.optString("purpose"),
        prescriber = o.optString("prescriber"),
        pharmacy = o.optString("pharmacy"),
        instructions = o.optString("instructions"),
        scheduleMinutes = o.ints("schedule_minutes"),
        weekdays = o.ints("weekdays"),
        isAsNeeded = o.optBoolean("is_as_needed"),
        isActive = o.optBoolean("is_active", true),
        startDate = o.instant("start_date") ?: Instant.EPOCH,
        endDate = o.instant("end_date"),
        tracksRefills = o.optBoolean("tracks_refills"),
        quantityRemaining = o.optDouble("quantity_remaining", 0.0),
        unitsPerDose = o.optDouble("units_per_dose", 1.0),
        refillThresholdDays = o.optInt("refill_threshold_days", 7),
        providerId = o.optStringOrNull("provider_id")?.let(UUID::fromString),
        pharmacyId = o.optStringOrNull("pharmacy_id")?.let(UUID::fromString),
        createdAt = o.instant("created_at") ?: Instant.EPOCH,
    )

    private fun dose(d: DoseLog) = JSONObject().apply {
        put("id", d.id.toString())
        put("medication_id", d.medicationId.toString())
        put("scheduled_at", d.scheduledAt.toString())
        put("status", d.status.raw)
        put("recorded_by_name", d.recordedBy)
        put("recorded_at", d.recordedAt.toString())
        put("note", d.note)
    }

    private fun dose(o: JSONObject) = DoseLog(
        id = UUID.fromString(o.getString("id")),
        medicationId = UUID.fromString(o.getString("medication_id")),
        scheduledAt = Instant.parse(o.getString("scheduled_at")),
        status = DoseStatus.of(o.optStringOrNull("status")),
        recordedBy = o.optString("recorded_by_name"),
        recordedAt = o.instant("recorded_at") ?: Instant.EPOCH,
        note = o.optString("note"),
    )

    private fun visit(v: Visit) = JSONObject().apply {
        put("id", v.id.toString())
        put("person_id", v.personId.toString())
        put("date", v.date.toString())
        put("provider", v.provider)
        put("specialty", v.specialty)
        put("reason", v.reason)
        put("notes", v.notes)
        put("follow_up", v.followUp)
        put("created_at", v.createdAt.toString())
    }

    private fun visit(o: JSONObject) = Visit(
        id = UUID.fromString(o.getString("id")),
        personId = UUID.fromString(o.getString("person_id")),
        date = Instant.parse(o.getString("date")),
        provider = o.optString("provider"),
        specialty = o.optString("specialty"),
        reason = o.optString("reason"),
        notes = o.optString("notes"),
        followUp = o.optString("follow_up"),
        createdAt = o.instant("created_at") ?: Instant.EPOCH,
    )

    private fun contact(c: EmergencyContact) = JSONObject().apply {
        put("id", c.id.toString())
        put("person_id", c.personId.toString())
        put("name", c.name)
        put("relationship", c.relationship)
        put("phone", c.phone)
        put("is_primary", c.isPrimary)
    }

    private fun contact(o: JSONObject) = EmergencyContact(
        id = UUID.fromString(o.getString("id")),
        personId = UUID.fromString(o.getString("person_id")),
        name = o.optString("name"),
        relationship = o.optString("relationship"),
        phone = o.optString("phone"),
        isPrimary = o.optBoolean("is_primary"),
    )

    private fun provider(p: Provider) = JSONObject().apply {
        put("id", p.id.toString())
        put("person_id", p.personId.toString())
        put("name", p.name)
        put("specialty", p.specialty)
        put("phone", p.phone)
        put("address", p.address)
        put("notes", p.notes)
        put("is_pharmacy", p.isPharmacy)
    }

    private fun provider(o: JSONObject) = Provider(
        id = UUID.fromString(o.getString("id")),
        personId = UUID.fromString(o.getString("person_id")),
        name = o.optString("name"),
        specialty = o.optString("specialty"),
        phone = o.optString("phone"),
        address = o.optString("address"),
        notes = o.optString("notes"),
        isPharmacy = o.optBoolean("is_pharmacy"),
    )

    private fun JSONObject.objects(key: String): List<JSONObject> {
        val array = optJSONArray(key) ?: return emptyList()
        return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
    }

    private fun JSONObject.strings(key: String): List<String> {
        val array = optJSONArray(key) ?: return emptyList()
        return (0 until array.length()).map { array.optString(it) }
    }

    private fun JSONObject.ints(key: String): List<Int> {
        val array = optJSONArray(key) ?: return emptyList()
        return (0 until array.length()).map { array.optInt(it) }
    }

    private fun JSONObject.optStringOrNull(key: String): String? =
        if (has(key) && !isNull(key)) optString(key).takeIf { it.isNotEmpty() } else null

    private fun JSONObject.instant(key: String): Instant? =
        optStringOrNull(key)?.let { runCatching { Instant.parse(it) }.getOrNull() }
}
