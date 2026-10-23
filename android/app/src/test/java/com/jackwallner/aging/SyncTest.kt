package com.jackwallner.aging

import com.jackwallner.aging.data.CareCodec
import com.jackwallner.aging.data.CareStore
import com.jackwallner.aging.data.MemoryPersistence
import com.jackwallner.aging.data.SignOutProtection
import com.jackwallner.aging.data.SyncEngine
import com.jackwallner.aging.data.SyncFailure
import com.jackwallner.aging.data.SyncRemote
import com.jackwallner.aging.data.SyncWire
import com.jackwallner.aging.model.DoseSlot
import com.jackwallner.aging.model.DoseStatus
import com.jackwallner.aging.model.EmergencyContact
import com.jackwallner.aging.model.Medication
import com.jackwallner.aging.model.OutboxStatus
import com.jackwallner.aging.model.OutboxEntry
import com.jackwallner.aging.model.Person
import com.jackwallner.aging.model.SyncEntity
import com.jackwallner.aging.model.SyncPage
import com.jackwallner.aging.model.Visit
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private val T0: Instant = Instant.parse("2026-10-21T08:00:00Z")

/** A clock that only moves when told, so updated_at comparisons are deterministic. */
private class Clock(var now: Instant = T0) {
    fun advance(seconds: Long = 60) { now = now.plusSeconds(seconds) }
}

private fun circleStore(circle: UUID?, clock: Clock) = CareStore(MemoryPersistence()) { clock.now }.also { it.circleId = circle }

/** `recordLocalChange` / `tombstone()` on iOS, derived from what changed. */
class SyncTrackerTest {
    private val circle = UUID.randomUUID()
    private val clock = Clock()

    @Test fun anEditInsideTheCircleIsQueuedOnce() {
        val store = circleStore(circle, clock)
        val mom = Person(name = "Eleanor", groupId = circle)
        store.upsertPerson(mom)
        store.upsertPerson(mom.copy(notes = "Hard of hearing"))
        assertEquals(1, store.state.sync.outbox.size)
        assertTrue(store.state.sync.meta.getValue(mom.id).isDirty)
    }

    @Test fun aPrivateRecordIsNeverQueuedByAnEdit() {
        val store = circleStore(circle, clock)
        val local = Person(name = "Dad")
        store.update { it.copy(people = it.people + local) }
        // Created while in a circle, so it joins the circle (iOS stamps `groups.activeGroupID`).
        assertEquals(circle, store.state.person(local.id)!!.groupId)
        val privateStore = circleStore(null, clock)
        privateStore.upsertPerson(Person(name = "Dad"))
        assertTrue(privateStore.state.sync.outbox.isEmpty())
    }

    @Test fun aRowLeftBehindByAnotherCircleIsNotQueued() {
        val store = circleStore(circle, clock)
        val stranded = Person(name = "Aunt May", groupId = UUID.randomUUID())
        store.applyRemote { it.copy(people = listOf(stranded)) }
        store.upsertPerson(stranded.copy(notes = "edited"))
        assertTrue(store.state.sync.outbox.isEmpty())
    }

    @Test fun deletingAPersonTombstonesThePersonOnly() {
        val store = circleStore(circle, clock)
        val mom = Person(name = "Eleanor", groupId = circle)
        val med = Medication(personId = mom.id, name = "Lisinopril", scheduleMinutes = listOf(480))
        store.applyRemote { it.copy(people = listOf(mom), medications = listOf(med)) }
        store.deletePerson(mom.id)
        val tombs = store.state.sync.tombstones
        assertEquals(listOf(mom.id), tombs.map { it.id })
        val payload = JSONObject(tombs.single().payload)
        assertEquals(circle.toString(), payload.getString("group_id"))
        assertFalse(payload.isNull("deleted_at"))
        assertEquals(listOf(mom.id), store.state.sync.outbox.map { it.entityId })
    }

    @Test fun undoingADoseTombstonesItAndTakingItAgainRevivesTheSameRow() {
        val store = circleStore(circle, clock)
        val mom = Person(name = "Eleanor", groupId = circle)
        val med = Medication(personId = mom.id, name = "Lisinopril", scheduleMinutes = listOf(480), startDate = T0.minusSeconds(86_400))
        store.applyRemote { it.copy(people = listOf(mom), medications = listOf(med)) }
        val slot = DoseSlot("slot", mom.id, med.id, med.name, "", T0, null, "")
        store.recordDose(slot, DoseStatus.TAKEN)
        store.clearDose(slot)
        assertEquals(1, store.state.sync.tombstones.size)
        store.recordDose(slot, DoseStatus.TAKEN)
        assertTrue(store.state.sync.tombstones.isEmpty())
        // One entry for the dose: re-taking it reuses the row, and the untracked medication itself did not change.
        assertEquals(1, store.state.sync.outbox.count { it.entity == SyncEntity.DOSE_LOG })
    }

    @Test fun sharingAPrivatePersonQueuesEverythingHangingOffThem() {
        val store = circleStore(circle, clock)
        val dad = Person(name = "Robert")
        val med = Medication(personId = dad.id, name = "Atorvastatin")
        val visit = Visit(personId = dad.id, date = T0)
        val contact = EmergencyContact(personId = dad.id, name = "Michael")
        store.applyRemote { it.copy(people = listOf(dad), medications = listOf(med), visits = listOf(visit), contacts = listOf(contact)) }
        store.adoptPerson(dad.id, circle)
        assertEquals(circle, store.state.person(dad.id)!!.groupId)
        assertEquals(setOf(dad.id, med.id, visit.id, contact.id), store.state.sync.outbox.map { it.entityId }.toSet())
    }

    @Test fun bookkeepingSurvivesARelaunch() {
        val persistence = MemoryPersistence()
        val store = CareStore(persistence) { clock.now }.also { it.circleId = circle }
        val mom = Person(name = "Eleanor", groupId = circle)
        store.upsertPerson(mom)
        store.deletePerson(mom.id)
        val reloaded = CareCodec.decode(persistence.text!!)
        assertEquals(store.state.sync, reloaded.sync)
    }
}

/** The wire format: column names, the noon rule, and what is left out. */
class SyncWireTest {
    private val group = UUID.randomUUID()

    @Test fun postgrestTimestampsWithMicrosecondsAndOffsetsParse() {
        assertEquals(Instant.parse("2026-10-21T09:12:33.123456Z"), SyncWire.instant("2026-10-21T09:12:33.123456+00:00"))
        assertEquals(Instant.parse("2026-10-21T07:12:33Z"), SyncWire.instant("2026-10-21T09:12:33+02:00"))
    }

    @Test fun aBareDayReadsAtNoonUtcSoTheBirthdayKeepsItsDate() {
        assertEquals(Instant.parse("1939-07-13T12:00:00Z"), SyncWire.instant("1939-07-13"))
        assertEquals(LocalDate.of(1939, 7, 13), SyncWire.day("1939-07-13T12:00:00+00:00"))
    }

    @Test fun aBirthDateIsSentAtNoonUtc() {
        val p = Person(name = "Eleanor", birthDate = LocalDate.of(1947, 4, 12))
        assertEquals("1947-04-12T12:00:00Z", SyncWire.person(p, group).getString("birth_date"))
    }

    @Test fun nullOptionalsAreLeftOutButDeletedAtIsAlwaysSent() {
        val o = SyncWire.person(Person(name = "Eleanor"), group)
        assertFalse(o.has("linked_user_id"))
        assertFalse(o.has("birth_date"))
        assertFalse(o.has("updated_at"))
        assertFalse(o.has("last_check_in_at"))
        assertTrue(o.has("deleted_at") && o.isNull("deleted_at"))
    }

    @Test fun aMedicationRoundTripsThroughTheWire() {
        val m = Medication(
            personId = UUID.randomUUID(), name = "Warfarin", strength = "5 mg", scheduleMinutes = listOf(480, 1200), weekdays = listOf(2, 4, 6),
            tracksRefills = true, quantityRemaining = 30.0, unitsPerDose = 1.0, startDate = T0, endDate = T0.plusSeconds(3600),
        )
        val wire = SyncWire.medication(m, group).put("updated_at", "2026-10-21T08:00:00.5+00:00")
        val back = SyncWire.medication(wire, m)
        assertEquals(m, back)
    }

    @Test fun pulledPersonKeepsLocalOnlyFields() {
        val local = Person(name = "Me", isSelf = true, createdAt = T0)
        val wire = SyncWire.person(local.copy(name = "Jack"), group).put("last_check_in_at", "2026-10-21T09:00:00+00:00")
        val back = SyncWire.person(wire, local)
        assertTrue(back.isSelf)
        assertEquals(T0, back.createdAt)
        assertEquals(group, back.groupId)
        assertEquals(Instant.parse("2026-10-21T09:00:00Z"), back.lastCheckInAt)
    }
}

/** Port of `SyncEngineTests.swift`, run against a scripted remote. */
class SyncEngineTest {
    private val group = UUID.randomUUID()
    private val clock = Clock()

    @Test fun signOutSyncsBeforeAllowingTheSharedVisitToBeRemoved() = runBlocking {
        val store = circleStore(group, clock)
        val mom = Person(name = "Mom", groupId = group)
        store.applyRemote { it.copy(people = listOf(mom)) }
        store.upsertVisit(Visit(personId = mom.id, provider = "Dr. Patel", date = T0))
        val remote = Remote()
        val warning = SignOutProtection.prepare(store) { SyncEngine(store, { clock.now }).sync(remote, group) }
        assertNull(warning)
        assertEquals(1, remote.pushes.count { it.first == SyncEntity.VISIT })
        assertTrue(store.state.sync.outbox.isEmpty())
    }

    @Test fun failedSignOutSyncNamesWhatWouldBeLostAndKeepsTheVisitForCancel() = runBlocking {
        for (failure in listOf(SyncFailure.Offline, SyncFailure.Rejected("Access changed"), SyncFailure.Server("Unavailable"))) {
            val store = circleStore(group, clock)
            val mom = Person(name = "Mom", groupId = group)
            store.applyRemote { it.copy(people = listOf(mom)) }
            store.upsertVisit(Visit(personId = mom.id, provider = "Dr. Patel", date = T0))
            val remote = Remote().apply { failPush = failure }
            val warning = SignOutProtection.prepare(store) { SyncEngine(store, { clock.now }).sync(remote, group) }
            assertTrue(warning!!.contains("1 visit"))
            assertTrue(warning.contains("permanently discard"))
            assertTrue(warning.contains("Cancel"))
            assertEquals(1, store.state.visits.size)
            assertEquals(1, store.state.sync.outbox.size)
        }
    }

    @Test fun signOutIncludesConflictsDeferredRetriesAndTombstonesWithoutDoubleCounting() = runBlocking {
        val store = circleStore(group, clock)
        val mom = Person(name = "Mom", groupId = group)
        store.applyRemote { it.copy(people = listOf(mom)) }
        val visit = Visit(personId = mom.id, date = T0)
        store.upsertVisit(visit)
        store.deleteVisit(visit.id)
        store.applyRemote { s -> s.copy(sync = s.sync.copy(outbox = listOf(
            s.sync.outbox.single().copy(status = OutboxStatus.RETRYING, notBefore = T0.plusSeconds(3600)),
            OutboxEntry(SyncEntity.MEDICATION, UUID.randomUUID(), status = OutboxStatus.NEEDS_REVIEW),
        ))) }
        val warning = SignOutProtection.prepare(store) {
            assertTrue(SyncEngine(store, { clock.now }).sync(Remote(), group).isComplete)
        }
        assertTrue(warning!!.contains("1 visit"))
        assertTrue(warning.contains("1 medication"))
        assertEquals(listOf("1 medication", "1 visit"), SignOutProtection.pendingChanges(store.state))
    }

    @Test fun signOutWithOnlyPrivateEditsNeedsNoSyncOrDiscardWarning() = runBlocking {
        val store = circleStore(null, clock)
        store.upsertPerson(Person(name = "Private record"))
        var synced = false
        assertNull(SignOutProtection.prepare(store) { synced = true })
        assertFalse(synced)
        assertEquals(1, store.state.people.size)
    }

    /** A Postgres table in miniature: server-owned updated_at, (updated_at, id) cursor order. */
    private inner class Remote : SyncRemote {
        val tables = SyncEntity.entries.associateWith { linkedMapOf<UUID, JSONObject>() }
        var offline = false
        var failPush: SyncFailure? = null
        var failPull: Set<SyncEntity> = emptySet()
        var tick = 0L
        val pushes = mutableListOf<Pair<SyncEntity, JSONObject>>()

        fun put(entity: SyncEntity, row: JSONObject): JSONObject {
            row.put("updated_at", clock.now.plusMillis(++tick).toString())
            if (!row.has("deleted_at")) row.put("deleted_at", JSONObject.NULL)
            tables.getValue(entity)[UUID.fromString(row.getString("id"))] = row
            return row
        }

        override suspend fun pull(entity: SyncEntity, groupId: UUID, after: SyncPage?, limit: Int): List<JSONObject> {
            if (offline) throw SyncFailure.Offline
            if (entity in failPull) throw SyncFailure.Server("relation does not exist")
            return tables.getValue(entity).values.filter { it.getString("group_id") == groupId.toString() }
                .sortedWith(compareBy({ SyncWire.instant(it.getString("updated_at")) }, { it.getString("id") }))
                .filter { r ->
                    after == null || SyncWire.instant(r.getString("updated_at"))!!.let { t -> t > after.updatedAt || (t == after.updatedAt && r.getString("id") > after.id.toString()) }
                }
                .take(limit).map { JSONObject(it.toString()) }
        }

        override suspend fun push(entity: SyncEntity, row: JSONObject) {
            if (offline) throw SyncFailure.Offline
            failPush?.let { throw it }
            pushes += entity to row
            val id = UUID.fromString(row.getString("id"))
            val merged = tables.getValue(entity)[id]?.let { e -> JSONObject(e.toString()).also { m -> row.keys().forEach { m.put(it, row.get(it)) } } } ?: row
            put(entity, merged)
        }
    }

    private fun personRow(id: UUID, name: String) = JSONObject().put("id", id.toString()).put("group_id", group.toString()).put("name", name)
        .put("relationship", "").put("blood_type", "").put("color_index", 0).put("allergies", org.json.JSONArray()).put("conditions", org.json.JSONArray()).put("notes", "")

    private fun medRow(id: UUID, person: UUID, name: String, minutes: List<Int> = listOf(480)) = SyncWire.medication(
        Medication(id = id, personId = person, name = name, scheduleMinutes = minutes, startDate = T0), group,
    ).apply { remove("deleted_at") }

    private fun sync(store: CareStore, remote: SyncRemote, pageSize: Int = 200) = runBlocking { SyncEngine(store, { clock.now }, pageSize).sync(remote, group) }

    @Test fun aRecordTypedOnOnePhoneArrivesOnAnother() {
        val remote = Remote()
        val a = circleStore(group, clock)
        val mom = Person(name = "Eleanor", groupId = group, birthDate = LocalDate.of(1947, 4, 12))
        a.upsertPerson(mom)
        a.upsertMedication(Medication(personId = mom.id, name = "Lisinopril", scheduleMinutes = listOf(480), startDate = T0))
        val pushed = sync(a, remote)
        assertTrue(pushed.isComplete)
        assertEquals(2, pushed.pushed)
        assertTrue(a.state.sync.outbox.isEmpty())
        assertFalse(a.state.sync.meta.getValue(mom.id).isDirty)

        val b = circleStore(group, clock)
        val pulled = sync(b, remote)
        assertEquals(2, pulled.pulled)
        assertEquals(LocalDate.of(1947, 4, 12), b.state.person(mom.id)!!.birthDate)
        assertEquals("Lisinopril", b.state.medicationsOf(mom.id).single().name)
        // A pulled row is not queued back.
        assertTrue(b.state.sync.outbox.isEmpty())
    }

    @Test fun pagesFollowTheCompoundCursorWithoutSkippingOrRepeating() {
        val remote = Remote()
        val mom = UUID.randomUUID()
        remote.put(SyncEntity.PERSON, personRow(mom, "Eleanor"))
        // Five medications sharing one updated_at, the transaction case the compound cursor exists for.
        val stamp = clock.now.plusSeconds(5).toString()
        repeat(5) { i ->
            val row = medRow(UUID.randomUUID(), mom, "Med $i").put("updated_at", stamp).put("deleted_at", JSONObject.NULL)
            remote.tables.getValue(SyncEntity.MEDICATION)[UUID.fromString(row.getString("id"))] = row
        }
        val b = circleStore(group, clock)
        sync(b, remote, pageSize = 2)
        assertEquals(5, b.state.medications.size)
        assertNotNull(b.state.sync.cursors[SyncEntity.MEDICATION])
        assertEquals(0, sync(b, remote, pageSize = 2).pulled)
    }

    @Test fun aChildWhosePersonHasNotArrivedStopsThePageInsteadOfLandingOrphaned() {
        val remote = Remote()
        val mom = UUID.randomUUID()
        remote.put(SyncEntity.PERSON, personRow(mom, "Eleanor"))
        remote.put(SyncEntity.MEDICATION, medRow(UUID.randomUUID(), mom, "Lisinopril"))
        remote.failPull = setOf(SyncEntity.PERSON)
        val b = circleStore(group, clock)
        val first = sync(b, remote)
        assertFalse(first.isComplete)
        assertTrue(b.state.medications.isEmpty())
        assertNull(b.state.sync.cursors[SyncEntity.MEDICATION])
        remote.failPull = emptySet()
        sync(b, remote)
        assertEquals(mom, b.state.medications.single().personId)
    }

    @Test fun aChildOfADeletedPersonIsDiscardedSoItsTableKeepsMoving() {
        val remote = Remote()
        val mom = UUID.randomUUID()
        remote.put(SyncEntity.PERSON, personRow(mom, "Eleanor").put("deleted_at", T0.toString()))
        remote.put(SyncEntity.MEDICATION, medRow(UUID.randomUUID(), mom, "Lisinopril"))
        val dad = UUID.randomUUID()
        remote.put(SyncEntity.PERSON, personRow(dad, "Robert"))
        remote.put(SyncEntity.MEDICATION, medRow(UUID.randomUUID(), dad, "Atorvastatin"))
        val b = circleStore(group, clock)
        assertTrue(sync(b, remote).isComplete)
        assertEquals(listOf("Atorvastatin"), b.state.medications.map { it.name })
    }

    @Test fun twoPeopleChangingOneDosageIsFlaggedWithBothReadings() {
        val remote = Remote()
        val a = circleStore(group, clock)
        val mom = Person(name = "Eleanor", groupId = group)
        val med = Medication(personId = mom.id, name = "Warfarin", strength = "5 mg", scheduleMinutes = listOf(480), startDate = T0)
        a.upsertPerson(mom); a.upsertMedication(med)
        sync(a, remote)
        // This phone goes offline and edits; the family edits later on the server.
        clock.advance()
        a.upsertMedication(med.copy(strength = "2.5 mg"))
        clock.advance()
        remote.put(SyncEntity.MEDICATION, JSONObject(remote.tables.getValue(SyncEntity.MEDICATION)[med.id].toString()).put("strength", "7.5 mg"))
        val outcome = sync(a, remote)
        assertEquals(1, outcome.conflicts)
        assertEquals("2.5 mg", a.state.medications.single().strength)
        val conflict = SyncEngine(a).conflicts().single()
        assertTrue(conflict.localSummary.contains("2.5 mg"))
        assertTrue(conflict.remoteSummary.contains("7.5 mg"))
        assertEquals("7.5 mg", remote.tables.getValue(SyncEntity.MEDICATION)[med.id]!!.getString("strength"))
    }

    @Test fun takingTheirsRewindsAndWritesTheFamilysVersion() {
        val remote = Remote()
        val a = circleStore(group, clock)
        val mom = Person(name = "Eleanor", groupId = group)
        val med = Medication(personId = mom.id, name = "Warfarin", strength = "5 mg", scheduleMinutes = listOf(480), startDate = T0)
        a.upsertPerson(mom); a.upsertMedication(med)
        sync(a, remote)
        clock.advance(); a.upsertMedication(med.copy(strength = "2.5 mg"))
        clock.advance(); remote.put(SyncEntity.MEDICATION, JSONObject(remote.tables.getValue(SyncEntity.MEDICATION)[med.id].toString()).put("strength", "7.5 mg"))
        sync(a, remote)
        SyncEngine(a, { clock.now }).resolveTakingRemote(med.id)
        sync(a, remote)
        assertEquals("7.5 mg", a.state.medications.single().strength)
        assertEquals(0, a.state.sync.conflictCount)
    }

    @Test fun keepingMineSendsThisPhonesVersion() {
        val remote = Remote()
        val a = circleStore(group, clock)
        val mom = Person(name = "Eleanor", groupId = group)
        val med = Medication(personId = mom.id, name = "Warfarin", strength = "5 mg", scheduleMinutes = listOf(480), startDate = T0)
        a.upsertPerson(mom); a.upsertMedication(med)
        sync(a, remote)
        clock.advance(); a.upsertMedication(med.copy(strength = "2.5 mg"))
        clock.advance(); remote.put(SyncEntity.MEDICATION, JSONObject(remote.tables.getValue(SyncEntity.MEDICATION)[med.id].toString()).put("strength", "7.5 mg"))
        sync(a, remote)
        SyncEngine(a, { clock.now }).resolveKeepingLocal(med.id)
        sync(a, remote)
        assertEquals("2.5 mg", remote.tables.getValue(SyncEntity.MEDICATION)[med.id]!!.getString("strength"))
        assertEquals(0, a.state.sync.conflictCount)
    }

    @Test fun aNewerLocalVisitNoteIsNotClobberedByAnOlderPull() {
        val remote = Remote()
        val a = circleStore(group, clock)
        val mom = Person(name = "Eleanor", groupId = group)
        val visit = Visit(personId = mom.id, date = T0, notes = "first")
        a.upsertPerson(mom); a.upsertVisit(visit)
        sync(a, remote)
        // The family's edit lands first, then this phone's later one before it syncs.
        clock.advance(); remote.put(SyncEntity.VISIT, JSONObject(remote.tables.getValue(SyncEntity.VISIT)[visit.id].toString()).put("notes", "theirs"))
        clock.advance(120); a.upsertVisit(visit.copy(notes = "mine, later"))
        sync(a, remote)
        assertEquals("mine, later", a.state.visits.single().notes)
        assertEquals("mine, later", remote.tables.getValue(SyncEntity.VISIT)[visit.id]!!.getString("notes"))
    }

    @Test fun aDeleteFromTheFamilyRemovesThePersonAndEverythingOnThem() {
        val remote = Remote()
        val a = circleStore(group, clock)
        val mom = Person(name = "Eleanor", groupId = group)
        a.upsertPerson(mom)
        a.upsertMedication(Medication(personId = mom.id, name = "Lisinopril", startDate = T0))
        sync(a, remote)
        clock.advance()
        remote.put(SyncEntity.PERSON, JSONObject(remote.tables.getValue(SyncEntity.PERSON)[mom.id].toString()).put("deleted_at", clock.now.toString()))
        sync(a, remote)
        assertTrue(a.state.people.isEmpty())
        assertTrue(a.state.medications.isEmpty())
        // Removed here, not queued back as a delete of its own.
        assertTrue(a.state.sync.outbox.isEmpty())
    }

    @Test fun aLocalDeleteReachesTheServerAsATombstoneAndIsThenForgotten() {
        val remote = Remote()
        val a = circleStore(group, clock)
        val mom = Person(name = "Eleanor", groupId = group)
        a.upsertPerson(mom)
        sync(a, remote)
        clock.advance()
        a.deletePerson(mom.id)
        sync(a, remote)
        assertFalse(remote.tables.getValue(SyncEntity.PERSON)[mom.id]!!.isNull("deleted_at"))
        assertTrue(a.state.sync.tombstones.isEmpty())
        assertTrue(a.state.sync.outbox.isEmpty())
    }

    @Test fun offlineKeepsTheQueueAndNeverClaimsASync() {
        val remote = Remote().apply { offline = true }
        val a = circleStore(group, clock)
        a.upsertPerson(Person(name = "Eleanor", groupId = group))
        val outcome = sync(a, remote)
        assertTrue(outcome.wasOffline)
        assertFalse(outcome.isComplete)
        assertEquals(1, a.state.sync.outbox.size)
        assertEquals(OutboxStatus.PENDING, a.state.sync.outbox.single().status)
    }

    @Test fun aServerErrorBacksOffAndARefusalAsksAPerson() {
        val remote = Remote().apply { failPush = SyncFailure.Server("column does not exist") }
        val a = circleStore(group, clock)
        a.upsertPerson(Person(name = "Eleanor", groupId = group))
        val outcome = sync(a, remote)
        assertFalse(outcome.isComplete)
        val entry = a.state.sync.outbox.single()
        assertEquals(OutboxStatus.RETRYING, entry.status)
        assertEquals(clock.now.plusSeconds(10), entry.notBefore)
        clock.advance(11)
        remote.failPush = SyncFailure.Rejected("new row violates row-level security policy")
        sync(a, remote)
        assertEquals(OutboxStatus.NEEDS_REVIEW, a.state.sync.outbox.single().status)
        assertEquals(1, a.state.sync.conflictCount)
    }

    @Test fun oneRefusedTableDoesNotStopThePush() {
        val remote = Remote().apply { failPull = setOf(SyncEntity.VISIT) }
        val a = circleStore(group, clock)
        a.upsertPerson(Person(name = "Eleanor", groupId = group))
        val outcome = sync(a, remote)
        assertEquals(1, outcome.pushed)
        assertFalse(outcome.isComplete)
    }

    @Test fun anEditMadeWhileItsPushIsInFlightStillGoes() {
        val a = circleStore(group, clock)
        val mom = Person(name = "Eleanor", groupId = group)
        a.upsertPerson(mom)
        val remote = object : SyncRemote {
            val inner = Remote()
            override suspend fun pull(entity: SyncEntity, groupId: UUID, after: SyncPage?, limit: Int) = inner.pull(entity, groupId, after, limit)
            override suspend fun push(entity: SyncEntity, row: JSONObject) {
                inner.push(entity, row)
                clock.advance()
                a.upsertPerson(mom.copy(notes = "typed during the push"))
            }
        }
        sync(a, remote)
        assertEquals(1, a.state.sync.outbox.size)
        assertTrue(a.state.sync.meta.getValue(mom.id).isDirty)
    }

    @Test fun aPrivateRecordIsNeverPushedEvenIfSomethingQueuedIt() {
        val remote = Remote()
        val a = circleStore(group, clock)
        val local = Person(name = "Dad")
        a.applyRemote { it.copy(people = listOf(local), sync = it.sync.copy(outbox = listOf(com.jackwallner.aging.model.OutboxEntry(SyncEntity.PERSON, local.id)))) }
        sync(a, remote)
        assertTrue(remote.pushes.isEmpty())
        assertTrue(a.state.sync.outbox.isEmpty())
    }
}
