package com.jackwallner.aging.data

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
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/**
 * The rows as Supabase stores them, column for column with the iOS DTOs in
 * `SyncRemote.swift`.
 *
 * Two encoding rules differ from a naive mapping, both on purpose:
 * - A null optional is left out, never sent as null, exactly like Swift's
 *   synthesized `Codable`. An upsert only writes the columns it names, so a
 *   column this phone does not know (`linked_user_id` set by `accept_invite`,
 *   `last_filled_at`) keeps the server's value.
 * - `deleted_at` is always sent. A dose re-recorded after an undo reuses its
 *   tombstoned id, and leaving the column out would keep the server row deleted
 *   while this phone shows it live.
 *
 * `updated_at` is never sent: the server owns it (`touch_updated_at`).
 */
object SyncWire {
    // MARK: Dates

    /** PostgREST writes `2026-10-21T09:12:33.123456+00:00`; a legacy `date` column writes a bare day. */
    fun instant(raw: String?): Instant? {
        if (raw.isNullOrBlank()) return null
        runCatching { return OffsetDateTime.parse(raw).toInstant() }
        runCatching { return Instant.parse(raw) }
        // A bare day reads at noon UTC, matching migration 0021 and `PostgrestCoding` on iOS.
        return runCatching { LocalDate.parse(raw).atTime(12, 0).toInstant(ZoneOffset.UTC) }.getOrNull()
    }

    /** Day-valued columns are stored at noon UTC, so the day survives every US time zone. */
    fun dayAtNoonUtc(day: LocalDate): String = day.atTime(12, 0).toInstant(ZoneOffset.UTC).toString()

    fun day(raw: String?): LocalDate? = instant(raw)?.atOffset(ZoneOffset.UTC)?.toLocalDate()

    // MARK: Rows to wire

    fun person(p: Person, groupId: UUID, deletedAt: Instant? = null) = JSONObject().apply {
        put("id", p.id.toString())
        put("group_id", groupId.toString())
        p.linkedUserId?.let { put("linked_user_id", it.toString()) }
        put("name", p.name)
        put("relationship", p.relationship)
        p.birthDate?.let { put("birth_date", dayAtNoonUtc(it)) }
        put("blood_type", p.bloodType)
        put("color_index", p.colorIndex)
        put("allergies", JSONArray(p.allergies))
        put("conditions", JSONArray(p.conditions))
        put("notes", p.notes)
        p.surrogateAttestedAt?.let { put("surrogate_attested_at", it.toString()) }
        putDeleted(deletedAt)
    }

    fun medication(m: Medication, groupId: UUID, deletedAt: Instant? = null) = JSONObject().apply {
        put("id", m.id.toString())
        put("group_id", groupId.toString())
        put("care_recipient_id", m.personId.toString())
        put("name", m.name)
        put("strength", m.strength)
        put("form", m.form.raw)
        put("purpose", m.purpose)
        put("prescriber", m.prescriber)
        put("pharmacy", m.pharmacy)
        m.providerId?.let { put("provider_id", it.toString()) }
        m.pharmacyId?.let { put("pharmacy_id", it.toString()) }
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
        putDeleted(deletedAt)
    }

    fun dose(d: DoseLog, groupId: UUID, deletedAt: Instant? = null) = JSONObject().apply {
        put("id", d.id.toString())
        put("group_id", groupId.toString())
        put("medication_id", d.medicationId.toString())
        put("scheduled_at", d.scheduledAt.toString())
        put("recorded_at", d.recordedAt.toString())
        put("status", d.status.raw)
        put("recorded_by_name", d.recordedBy)
        put("note", d.note)
        putDeleted(deletedAt)
    }

    fun visit(v: Visit, groupId: UUID, deletedAt: Instant? = null) = JSONObject().apply {
        put("id", v.id.toString())
        put("group_id", groupId.toString())
        put("care_recipient_id", v.personId.toString())
        put("date", v.date.toString())
        put("provider", v.provider)
        v.providerId?.let { put("provider_id", it.toString()) }
        put("specialty", v.specialty)
        put("reason", v.reason)
        put("notes", v.notes)
        put("follow_up", v.followUp)
        v.nextAppointment?.let { put("next_appointment", it.toString()) }
        putDeleted(deletedAt)
    }

    fun contact(c: EmergencyContact, groupId: UUID, deletedAt: Instant? = null) = JSONObject().apply {
        put("id", c.id.toString())
        put("group_id", groupId.toString())
        put("care_recipient_id", c.personId.toString())
        put("name", c.name)
        put("relationship", c.relationship)
        put("phone", c.phone)
        put("is_primary", c.isPrimary)
        putDeleted(deletedAt)
    }

    fun provider(p: Provider, groupId: UUID, deletedAt: Instant? = null) = JSONObject().apply {
        put("id", p.id.toString())
        put("group_id", groupId.toString())
        put("care_recipient_id", p.personId.toString())
        put("name", p.name)
        put("specialty", p.specialty)
        put("phone", p.phone)
        put("address", p.address)
        put("portal_url", p.portalUrl)
        put("notes", p.notes)
        put("is_pharmacy", p.isPharmacy)
        putDeleted(deletedAt)
    }

    private fun JSONObject.putDeleted(deletedAt: Instant?) {
        put("deleted_at", deletedAt?.toString() ?: JSONObject.NULL)
    }

    // MARK: Wire to rows

    /** Local-only fields ([Person.isSelf], [Person.createdAt]) come from [local] when the row is already held. */
    fun person(o: JSONObject, local: Person?) = Person(
        id = o.uuid("id"),
        name = o.text("name"),
        relationship = o.text("relationship"),
        birthDate = day(o.textOrNull("birth_date")),
        bloodType = o.text("blood_type"),
        isSelf = local?.isSelf ?: false,
        allergies = o.strings("allergies"),
        conditions = o.strings("conditions"),
        notes = o.text("notes"),
        surrogateAttestedAt = instant(o.textOrNull("surrogate_attested_at")),
        createdAt = local?.createdAt ?: instant(o.textOrNull("created_at")) ?: Instant.now(),
        groupId = o.uuidOrNull("group_id"),
        linkedUserId = o.uuidOrNull("linked_user_id"),
        colorIndex = o.optInt("color_index", 0),
        lastCheckInAt = instant(o.textOrNull("last_check_in_at")),
    )

    fun medication(o: JSONObject, local: Medication?) = Medication(
        id = o.uuid("id"),
        personId = o.uuid("care_recipient_id"),
        name = o.text("name"),
        strength = o.text("strength"),
        form = MedicationForm.of(o.textOrNull("form")),
        purpose = o.text("purpose"),
        prescriber = o.text("prescriber"),
        pharmacy = o.text("pharmacy"),
        instructions = o.text("instructions"),
        scheduleMinutes = o.ints("schedule_minutes"),
        weekdays = o.ints("weekdays"),
        isAsNeeded = o.optBoolean("is_as_needed"),
        isActive = o.optBoolean("is_active", true),
        startDate = instant(o.textOrNull("start_date")) ?: Instant.now(),
        endDate = instant(o.textOrNull("end_date")),
        tracksRefills = o.optBoolean("tracks_refills"),
        quantityRemaining = o.optDouble("quantity_remaining", 0.0),
        unitsPerDose = o.optDouble("units_per_dose", 1.0),
        refillThresholdDays = o.optInt("refill_threshold_days", 7),
        providerId = o.uuidOrNull("provider_id"),
        pharmacyId = o.uuidOrNull("pharmacy_id"),
        createdAt = local?.createdAt ?: Instant.now(),
    )

    fun dose(o: JSONObject) = DoseLog(
        id = o.uuid("id"),
        medicationId = o.uuid("medication_id"),
        scheduledAt = instant(o.textOrNull("scheduled_at")) ?: Instant.EPOCH,
        status = DoseStatus.of(o.textOrNull("status")),
        recordedBy = o.text("recorded_by_name"),
        recordedAt = instant(o.textOrNull("recorded_at")) ?: Instant.now(),
        note = o.text("note"),
    )

    fun visit(o: JSONObject, local: Visit?) = Visit(
        id = o.uuid("id"),
        personId = o.uuid("care_recipient_id"),
        date = instant(o.textOrNull("date")) ?: Instant.now(),
        provider = o.text("provider"),
        specialty = o.text("specialty"),
        reason = o.text("reason"),
        notes = o.text("notes"),
        followUp = o.text("follow_up"),
        createdAt = local?.createdAt ?: Instant.now(),
        providerId = o.uuidOrNull("provider_id"),
        nextAppointment = instant(o.textOrNull("next_appointment")),
    )

    fun contact(o: JSONObject) = EmergencyContact(
        id = o.uuid("id"),
        personId = o.uuid("care_recipient_id"),
        name = o.text("name"),
        relationship = o.text("relationship"),
        phone = o.text("phone"),
        isPrimary = o.optBoolean("is_primary"),
    )

    fun provider(o: JSONObject) = Provider(
        id = o.uuid("id"),
        personId = o.uuid("care_recipient_id"),
        name = o.text("name"),
        specialty = o.text("specialty"),
        phone = o.text("phone"),
        address = o.text("address"),
        notes = o.text("notes"),
        isPharmacy = o.optBoolean("is_pharmacy"),
        portalUrl = o.text("portal_url"),
    )

    // MARK: Helpers

    fun JSONObject.textOrNull(key: String): String? = if (has(key) && !isNull(key)) optString(key) else null

    private fun JSONObject.text(key: String): String = textOrNull(key).orEmpty()

    fun JSONObject.uuid(key: String): UUID = UUID.fromString(getString(key))

    fun JSONObject.uuidOrNull(key: String): UUID? = textOrNull(key)?.takeIf { it.isNotEmpty() }?.let(UUID::fromString)

    private fun JSONObject.strings(key: String): List<String> {
        val array = optJSONArray(key) ?: return emptyList()
        return (0 until array.length()).map { array.optString(it) }
    }

    private fun JSONObject.ints(key: String): List<Int> {
        val array = optJSONArray(key) ?: return emptyList()
        return (0 until array.length()).map { array.optInt(it) }
    }
}
