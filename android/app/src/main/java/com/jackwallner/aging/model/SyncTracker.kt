package com.jackwallner.aging.model

import com.jackwallner.aging.data.SyncWire
import java.time.Instant
import java.util.UUID
import org.json.JSONObject

/**
 * Turns one local write into sync bookkeeping, the Android form of
 * `recordLocalChange` and `tombstone()` on iOS.
 *
 * Rules carried over:
 * - A changed or new row is marked dirty with a fresh `updatedAt` (the conflict
 *   rule compares it) and queued, but only when it belongs to the circle this
 *   phone is in. A private record is never queued by an edit.
 * - A removed row becomes a [Tombstone] holding its wire form, because the push
 *   has to send something and the live row is gone.
 * - Removing a person tombstones the person only. Their medications, visits and
 *   the rest leave this phone with them and are cleared on the other phones by
 *   the same rule when the person's tombstone arrives, exactly as on iOS.
 *   Likewise a medication's doses go with it.
 * - Re-creating a row whose tombstone is still waiting (a dose undone and taken
 *   again keeps its derived id) drops the tombstone: the live row is the truth.
 */
object SyncTracker {
    fun track(old: CareState, raw: CareState, circleId: UUID?, now: Instant): CareState {
        val oldPeople = old.people.map { it.id }.toSet()
        val next = if (circleId == null) raw else raw.copy(
            people = raw.people.map { if (it.id !in oldPeople && it.groupId == null) it.copy(groupId = circleId) else it },
        )
        val book = Book(next.sync, now)
        val removedPeople = oldPeople - next.people.map { it.id }.toSet()
        val removedMeds = old.medications.map { it.id }.toSet() - next.medications.map { it.id }.toSet()

        fun <T> diff(
            entity: SyncEntity,
            before: List<T>,
            after: List<T>,
            id: (T) -> UUID,
            groupIn: (T, CareState) -> UUID?,
            cascaded: (T) -> Boolean,
            wire: (T, UUID, Instant) -> JSONObject,
        ) {
            val beforeById = before.associateBy(id)
            val afterIds = HashSet<UUID>()
            for (row in after) {
                val rowId = id(row)
                afterIds += rowId
                if (beforeById[rowId] == row) continue
                book.touched(rowId)
                val group = groupIn(row, next)
                if (group != null && group == circleId) book.enqueue(entity, rowId)
            }
            for ((rowId, row) in beforeById) {
                if (rowId in afterIds) continue
                val group = groupIn(row, old)
                if (group != null && group == circleId && !cascaded(row)) {
                    book.tombstone(Tombstone(entity, rowId, now, wire(row, group, now).toString()))
                    book.enqueue(entity, rowId)
                } else {
                    book.forget(rowId)
                }
            }
        }

        diff(SyncEntity.PERSON, old.people, next.people, { it.id }, { p, _ -> p.groupId }, { false }, SyncWire::person)
        diff(SyncEntity.PROVIDER, old.providers, next.providers, { it.id }, { r, s -> s.person(r.personId)?.groupId },
            { it.personId in removedPeople }, SyncWire::provider)
        diff(SyncEntity.MEDICATION, old.medications, next.medications, { it.id }, { r, s -> s.person(r.personId)?.groupId },
            { it.personId in removedPeople }, SyncWire::medication)
        diff(SyncEntity.DOSE_LOG, old.doses, next.doses, { it.id }, { r, s -> groupOfMedication(r.medicationId, s) },
            { it.medicationId in removedMeds }, SyncWire::dose)
        diff(SyncEntity.VISIT, old.visits, next.visits, { it.id }, { r, s -> s.person(r.personId)?.groupId },
            { it.personId in removedPeople }, SyncWire::visit)
        diff(SyncEntity.EMERGENCY_CONTACT, old.contacts, next.contacts, { it.id }, { r, s -> s.person(r.personId)?.groupId },
            { it.personId in removedPeople }, SyncWire::contact)

        return next.copy(sync = book.result())
    }

    /** Queues one person and every row hanging off them, the Android `adoptPerson`. */
    fun adopt(state: CareState, personId: UUID, now: Instant): CareState {
        val book = Book(state.sync, now)
        fun add(entity: SyncEntity, id: UUID) {
            book.touched(id)
            book.enqueue(entity, id)
        }
        add(SyncEntity.PERSON, personId)
        state.providers.filter { it.personId == personId }.forEach { add(SyncEntity.PROVIDER, it.id) }
        val meds = state.medicationsOf(personId)
        meds.forEach { add(SyncEntity.MEDICATION, it.id) }
        // Dose logs hang off the medication, not the person, so a sweep by person alone leaves the history behind.
        val medIds = meds.map { it.id }.toSet()
        state.doses.filter { it.medicationId in medIds }.forEach { add(SyncEntity.DOSE_LOG, it.id) }
        state.visitsOf(personId).forEach { add(SyncEntity.VISIT, it.id) }
        state.contacts.filter { it.personId == personId }.forEach { add(SyncEntity.EMERGENCY_CONTACT, it.id) }
        return state.copy(sync = book.result())
    }

    fun groupOfMedication(medicationId: UUID, state: CareState): UUID? =
        state.medications.firstOrNull { it.id == medicationId }?.let { state.person(it.personId)?.groupId }

    private class Book(start: SyncState, private val now: Instant) {
        private val meta = start.meta.toMutableMap()
        private val tombstones = start.tombstones.toMutableList()
        private val outbox = start.outbox.toMutableList()
        private val cursors = start.cursors

        fun touched(id: UUID) {
            meta[id] = RowMeta(now, isDirty = true)
            tombstones.removeAll { it.id == id }
        }

        fun tombstone(t: Tombstone) {
            meta.remove(t.id)
            tombstones.removeAll { it.id == t.id }
            tombstones += t
        }

        /** Nothing to send for a row that never belonged to the circle. */
        fun forget(id: UUID) {
            meta.remove(id)
            outbox.removeAll { it.entityId == id && it.status != OutboxStatus.NEEDS_REVIEW }
        }

        /**
         * One entry per row. The push reads the row as it is when it goes, so a
         * second edit needs no second entry; a row waiting on a person's
         * decision keeps that one entry until they make it.
         */
        fun enqueue(entity: SyncEntity, id: UUID) {
            if (outbox.any { it.entityId == id }) return
            outbox += OutboxEntry(entity, id, createdAt = now)
        }

        fun result() = SyncState(meta, tombstones, outbox, cursors)
    }
}
