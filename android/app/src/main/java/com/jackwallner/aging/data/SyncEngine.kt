package com.jackwallner.aging.data

import com.jackwallner.aging.data.SyncWire.textOrNull
import com.jackwallner.aging.data.SyncWire.uuid
import com.jackwallner.aging.model.CareState
import com.jackwallner.aging.model.Medication
import com.jackwallner.aging.model.OutboxEntry
import com.jackwallner.aging.model.OutboxStatus
import com.jackwallner.aging.model.Person
import com.jackwallner.aging.model.RowMeta
import com.jackwallner.aging.model.SyncEntity
import com.jackwallner.aging.model.SyncPage
import com.jackwallner.aging.model.SyncTracker
import java.io.IOException
import java.time.Instant
import java.util.UUID
import kotlin.math.pow
import org.json.JSONException
import org.json.JSONObject

/** Why a sync request failed, which decides whether the outbox retries or gives up. */
sealed class SyncFailure(message: String) : Exception(message) {
    /** Network. Keep the entry queued and try later. */
    object Offline : SyncFailure("No connection.")

    /** Refused on authorization grounds (RLS, 42501). Retrying cannot fix it. */
    class Rejected(message: String) : SyncFailure(message)

    class Server(message: String) : SyncFailure(message)
}

/** Fronted by an interface so the engine runs against a fake on the JVM (`SyncRemote` on iOS). */
interface SyncRemote {
    suspend fun pull(entity: SyncEntity, groupId: UUID, after: SyncPage?, limit: Int): List<JSONObject>
    suspend fun push(entity: SyncEntity, row: JSONObject)
}

class SupabaseSyncRemote(private val client: SupabaseClient) : SyncRemote {
    override suspend fun pull(entity: SyncEntity, groupId: UUID, after: SyncPage?, limit: Int): List<JSONObject> = classify {
        val query = StringBuilder("${entity.table}?select=*&group_id=eq.$groupId")
        if (after != null) {
            // Strictly after (updated_at, id), the compound comparison PostgREST spells with `or`.
            val t = after.updatedAt.toString()
            query.append("&or=").append(encode("(updated_at.gt.$t,and(updated_at.eq.$t,id.gt.${after.id}))"))
        }
        query.append("&order=updated_at.asc,id.asc&limit=$limit")
        val array = org.json.JSONArray(client.select(query.toString()))
        (0 until array.length()).map { array.getJSONObject(it) }
    }

    override suspend fun push(entity: SyncEntity, row: JSONObject) = classify { client.upsert(entity.table, "id", row) }

    private fun encode(value: String) = java.net.URLEncoder.encode(value, "UTF-8")

    private suspend fun <T> classify(block: suspend () -> T): T = try {
        block()
    } catch (e: SupabaseError.Http) {
        // 42501 is insufficient_privilege, what RLS answers when this user may no longer write the row.
        if (e.code == "42501" || e.code == "PGRST301") throw SyncFailure.Rejected(e.message.orEmpty())
        throw SyncFailure.Server(e.message.orEmpty())
    } catch (e: SupabaseError) {
        throw SyncFailure.Server(e.message.orEmpty())
    } catch (e: JSONException) {
        // A row this app cannot read is a schema disagreement, not a bad network. Said so, not hidden as offline.
        throw SyncFailure.Server("This app is out of date for the server's data.")
    } catch (e: IOException) {
        throw SyncFailure.Offline
    }
}

/**
 * Port of `SyncEngine.swift` over the Android [CareStore]. The store stays the
 * source of truth for reading: sync writes into it and never sits in front of it.
 *
 * Pull rules, unchanged from iOS: parents before children; a child whose parent
 * has not arrived yet stops the page (the cursor never passes an unwritten row)
 * unless the parent's table has finished, in which case the parent was deleted
 * and the child is discarded; every row is bound to its parent on every apply.
 * Person and medication flag a real conflict for a human; dose logs, visits,
 * contacts and providers are last-writer-wins, compared, never pull-clobbers-local.
 *
 * One deliberate difference: a dirty person or medication that is newer than
 * the incoming row is kept. iOS writes the older server copy over it and loses
 * the edit; the comment on `shouldKeepLocal` there describes the same bug for
 * visits, fixed only for the last-writer-wins tables.
 */
class SyncEngine(
    private val store: CareStore,
    private val clock: () -> Instant = Instant::now,
    private val pageSize: Int = 200,
) {
    data class Outcome(
        val pulled: Int = 0,
        val pushed: Int = 0,
        val conflicts: Int = 0,
        val needsReview: Int = 0,
        val wasOffline: Boolean = false,
        /** The first thing that went wrong, phrased for a person. Null only when the cycle completed. */
        val failure: String? = null,
    ) {
        val isComplete: Boolean get() = failure == null
    }

    enum class ApplyOutcome { APPLIED, DISCARDED, DEFERRED }

    suspend fun sync(remote: SyncRemote, groupId: UUID): Outcome {
        var failure: Throwable? = null
        val pulled = pullAll(remote, groupId) { if (failure == null) failure = it }
        var pushed = 0
        var needsReview = 0
        try {
            val result = pushOutbox(remote, groupId)
            pushed = result.pushed
            needsReview = result.needsReview
            if (failure == null && result.failure != null) failure = SyncFailure.Server(result.failure)
        } catch (e: SyncFailure) {
            if (failure == null) failure = e
        }
        return Outcome(
            pulled = pulled,
            pushed = pushed,
            conflicts = store.state.sync.conflictCount,
            needsReview = needsReview,
            wasOffline = failure is SyncFailure.Offline,
            failure = failure?.let(::describe),
        )
    }

    private fun describe(error: Throwable): String = when (error) {
        is SyncFailure.Offline -> "No connection."
        else -> error.message?.takeIf { it.isNotBlank() } ?: "The server refused the change."
    }

    // MARK: - Pull

    private suspend fun pullAll(remote: SyncRemote, groupId: UUID, onFailure: (Throwable) -> Unit): Int {
        var applied = 0
        val settled = mutableSetOf<SyncEntity>()
        for (entity in SyncEntity.pullOrder) {
            try {
                val (count, complete) = pull(entity, remote, groupId, settled)
                applied += count
                if (complete) settled += entity
            } catch (e: SyncFailure) {
                // Per table, deliberately: one table refused today must not stop the rest, or the push.
                onFailure(e)
            }
        }
        return applied
    }

    private suspend fun pull(entity: SyncEntity, remote: SyncRemote, groupId: UUID, settled: Set<SyncEntity>): Pair<Int, Boolean> {
        var applied = 0
        var page = store.state.sync.cursors[entity]
        while (true) {
            val batch = remote.pull(entity, groupId, page, pageSize)
            if (batch.isEmpty()) break
            var deferred = false
            store.applyRemote { start ->
                var s = start
                var last: SyncPage? = null
                for (row in batch) {
                    val (next, outcome) = applyRow(s, entity, row, settled)
                    s = next
                    when (outcome) {
                        ApplyOutcome.APPLIED -> { applied++; last = pageOf(row) ?: last }
                        ApplyOutcome.DISCARDED -> last = pageOf(row) ?: last
                        ApplyOutcome.DEFERRED -> { deferred = true }
                    }
                    if (deferred) break
                }
                // Advanced only from the server's own updated_at, never the device clock.
                last?.let { page = it; s = s.copy(sync = s.sync.copy(cursors = s.sync.cursors + (entity to it))) }
                s
            }
            if (deferred) return applied to false
            if (batch.size < pageSize) break
        }
        return applied to true
    }

    private fun pageOf(row: JSONObject): SyncPage? {
        val updated = SyncWire.instant(row.textOrNull("updated_at")) ?: return null
        return SyncPage(updated, row.uuid("id"))
    }

    // MARK: - Applying one pulled row (pure, so the rules are unit-tested without a server)

    fun applyRow(s: CareState, entity: SyncEntity, row: JSONObject, settled: Set<SyncEntity>): Pair<CareState, ApplyOutcome> {
        val id = row.uuid("id")
        val deleted = row.textOrNull("deleted_at") != null
        val serverUpdated = SyncWire.instant(row.textOrNull("updated_at"))
        val tomb = s.sync.tombstone(id)
        val held = isLive(s, entity, id) || tomb != null

        if (!deleted && !held) {
            val parent = parentOf(s, entity, row)
            if (parent != null && !parent.second) {
                return s to if (parent.first in settled) ApplyOutcome.DISCARDED else ApplyOutcome.DEFERRED
            }
        }

        val meta = s.sync.meta[id]
        val localDirty = tomb != null || meta?.isDirty == true
        val localUpdated = tomb?.deletedAt ?: meta?.updatedAt ?: Instant.EPOCH

        if (held && entity.flagsConflicts) {
            // A human decides when two people changed a person or a dose instruction.
            if (localDirty && serverUpdated != null && (serverUpdated > localUpdated || deleted)) {
                return flagConflict(s, entity, id, localSummary(s, entity, id), remoteSummary(entity, row, deleted)) to ApplyOutcome.APPLIED
            }
            if (localDirty) return s to ApplyOutcome.APPLIED
        } else if (held) {
            if (localDirty && (serverUpdated == null || localUpdated > serverUpdated)) return s to ApplyOutcome.APPLIED
            // A delete made here stands until it has been pushed, as on iOS.
            if (tomb != null) return s to ApplyOutcome.APPLIED
        }

        if (deleted) return (if (held) removeLocally(s, entity, id) else s) to ApplyOutcome.APPLIED
        val written = write(s, entity, row)
        val cleaned = written.copy(sync = written.sync.copy(meta = written.sync.meta + (id to RowMeta(serverUpdated ?: clock(), isDirty = false))))
        return cleaned to ApplyOutcome.APPLIED
    }

    private val SyncEntity.flagsConflicts: Boolean get() = this == SyncEntity.PERSON || this == SyncEntity.MEDICATION

    private fun isLive(s: CareState, entity: SyncEntity, id: UUID): Boolean = when (entity) {
        SyncEntity.PERSON -> s.people.any { it.id == id }
        SyncEntity.PROVIDER -> s.providers.any { it.id == id }
        SyncEntity.MEDICATION -> s.medications.any { it.id == id }
        SyncEntity.DOSE_LOG -> s.doses.any { it.id == id }
        SyncEntity.VISIT -> s.visits.any { it.id == id }
        SyncEntity.EMERGENCY_CONTACT -> s.contacts.any { it.id == id }
    }

    /** The table a row's parent comes from and whether that parent is on this phone. Null when it has none. */
    private fun parentOf(s: CareState, entity: SyncEntity, row: JSONObject): Pair<SyncEntity, Boolean>? = when (entity) {
        SyncEntity.PERSON -> null
        SyncEntity.DOSE_LOG -> {
            val medId = row.uuid("medication_id")
            SyncEntity.MEDICATION to s.medications.any { it.id == medId }
        }
        else -> {
            val personId = row.uuid("care_recipient_id")
            SyncEntity.PERSON to s.people.any { it.id == personId }
        }
    }

    private fun <T> List<T>.upsert(row: T, id: (T) -> UUID): List<T> {
        val rowId = id(row)
        return if (any { id(it) == rowId }) map { if (id(it) == rowId) row else it } else this + row
    }

    private fun write(s: CareState, entity: SyncEntity, row: JSONObject): CareState = when (entity) {
        SyncEntity.PERSON -> {
            val local = s.person(row.uuid("id"))
            s.copy(people = s.people.upsert(SyncWire.person(row, local)) { it.id })
        }
        SyncEntity.PROVIDER -> s.copy(providers = s.providers.upsert(SyncWire.provider(row)) { it.id })
        SyncEntity.MEDICATION -> {
            val local = s.medications.firstOrNull { it.id == row.uuid("id") }
            s.copy(medications = s.medications.upsert(SyncWire.medication(row, local)) { it.id })
        }
        SyncEntity.DOSE_LOG -> s.copy(doses = s.doses.upsert(SyncWire.dose(row)) { it.id })
        SyncEntity.VISIT -> {
            val local = s.visits.firstOrNull { it.id == row.uuid("id") }
            s.copy(visits = s.visits.upsert(SyncWire.visit(row, local)) { it.id })
        }
        SyncEntity.EMERGENCY_CONTACT -> s.copy(contacts = s.contacts.upsert(SyncWire.contact(row)) { it.id })
    }

    // MARK: - Push

    private data class PushResult(val pushed: Int, val needsReview: Int, val failure: String?)

    private suspend fun pushOutbox(remote: SyncRemote, groupId: UUID): PushResult {
        val now = clock()
        val work = store.state.sync.outbox
            .filter { it.status != OutboxStatus.NEEDS_REVIEW && !it.notBefore.isAfter(now) }
            .sortedBy { it.createdAt }
        var pushed = 0
        var needsReview = 0
        var failure: String? = null
        for (entry in work) {
            val state = store.state
            val version = state.sync.meta[entry.entityId]?.updatedAt ?: state.sync.tombstone(entry.entityId)?.deletedAt
            val payload = payload(state, entry, groupId)
            if (payload == null) {
                // Gone, or not the circle's to receive: nothing can or should be sent.
                store.applyRemote { s -> s.copy(sync = s.sync.copy(outbox = s.sync.outbox.filter { it.entityId != entry.entityId })) }
                continue
            }
            try {
                remote.push(entry.entity, payload)
                store.applyRemote { s -> markSynced(s, entry, version) }
                pushed++
            } catch (e: SyncFailure.Offline) {
                // Stop: the rest would fail the same way, on what may be someone's only phone.
                throw e
            } catch (e: SyncFailure) {
                if (failure == null) failure = describe(e)
                val attempts = entry.attempts + 1
                val review = e is SyncFailure.Rejected || attempts >= MAX_ATTEMPTS
                if (review) needsReview++
                val updated = entry.copy(
                    attempts = attempts,
                    lastError = e.message.orEmpty(),
                    status = if (review) OutboxStatus.NEEDS_REVIEW else OutboxStatus.RETRYING,
                    notBefore = if (review) entry.notBefore else clock().plusSeconds((2.0.pow(attempts) * 5).toLong()),
                )
                store.applyRemote { s -> s.copy(sync = s.sync.copy(outbox = s.sync.outbox.map { if (it.entityId == entry.entityId) updated else it })) }
            }
        }
        return PushResult(pushed, needsReview, failure)
    }

    /** The wire row for one entry, or null when there is nothing this circle should receive. */
    fun payload(s: CareState, entry: OutboxEntry, groupId: UUID): JSONObject? {
        val id = entry.entityId
        s.sync.tombstone(id)?.let { tomb ->
            val row = JSONObject(tomb.payload)
            return row.takeIf { it.optString("group_id") == groupId.toString() }
        }
        fun inCircle(personId: UUID) = s.person(personId)?.groupId == groupId
        return when (entry.entity) {
            SyncEntity.PERSON -> s.person(id)?.takeIf { it.groupId == groupId }?.let { SyncWire.person(it, groupId) }
            SyncEntity.PROVIDER -> s.providers.firstOrNull { it.id == id }?.takeIf { inCircle(it.personId) }?.let { SyncWire.provider(it, groupId) }
            SyncEntity.MEDICATION -> s.medications.firstOrNull { it.id == id }?.takeIf { inCircle(it.personId) }?.let { SyncWire.medication(it, groupId) }
            SyncEntity.DOSE_LOG -> s.doses.firstOrNull { it.id == id }
                ?.takeIf { SyncTracker.groupOfMedication(it.medicationId, s) == groupId }?.let { SyncWire.dose(it, groupId) }
            SyncEntity.VISIT -> s.visits.firstOrNull { it.id == id }?.takeIf { inCircle(it.personId) }?.let { SyncWire.visit(it, groupId) }
            SyncEntity.EMERGENCY_CONTACT -> s.contacts.firstOrNull { it.id == id }?.takeIf { inCircle(it.personId) }?.let { SyncWire.contact(it, groupId) }
        }
    }

    /**
     * Clears the entry and the dirty flag, and the tombstone once it has
     * reached the server. A row edited again while its push was in flight keeps
     * both, so that later edit still goes.
     */
    private fun markSynced(s: CareState, entry: OutboxEntry, version: Instant?): CareState {
        val id = entry.entityId
        val current = s.sync.meta[id]?.updatedAt ?: s.sync.tombstone(id)?.deletedAt
        if (current != version) return s
        val meta = s.sync.meta[id]
        return s.copy(
            sync = s.sync.copy(
                meta = if (meta != null) s.sync.meta + (id to meta.copy(isDirty = false)) else s.sync.meta,
                tombstones = s.sync.tombstones.filter { it.id != id },
                outbox = s.sync.outbox.filter { it.entityId != id },
            ),
        )
    }

    // MARK: - Conflicts

    data class ConflictSummary(
        val id: UUID,
        val entity: SyncEntity,
        val personName: String,
        val title: String,
        val localSummary: String,
        val remoteSummary: String,
    )

    fun conflicts(s: CareState = store.state): List<ConflictSummary> =
        s.sync.outbox.filter { it.status == OutboxStatus.NEEDS_REVIEW }.sortedBy { it.createdAt }.map { entry ->
            val person = personFor(s, entry.entity, entry.entityId)
            ConflictSummary(
                id = entry.entityId,
                entity = entry.entity,
                personName = person?.displayLabel.orEmpty(),
                title = titleFor(s, entry.entity, entry.entityId),
                localSummary = entry.localSummary,
                remoteSummary = entry.remoteSummary.ifEmpty { entry.lastError },
            )
        }

    /** Send this phone's version: the queued write goes back in the queue. */
    fun resolveKeepingLocal(id: UUID) = store.applyRemote { s ->
        s.copy(sync = s.sync.copy(outbox = s.sync.outbox.map {
            if (it.entityId == id) it.copy(status = OutboxStatus.PENDING, attempts = 0, notBefore = Instant.EPOCH, lastError = "") else it
        }))
    }

    /**
     * Take the family's version. Their copy is not on the phone (the pull kept
     * ours), so the queued write is dropped, the row marked clean, and that
     * table's cursor rewound to the start so the next sync writes their copy in
     * through the ordinary path. A whole-table re-pull is cheap at family scale
     * and cannot land on the wrong side of the row.
     */
    fun resolveTakingRemote(id: UUID) = store.applyRemote { s ->
        val entry = s.sync.outbox.firstOrNull { it.entityId == id } ?: return@applyRemote s
        val meta = s.sync.meta[id]
        s.copy(
            sync = s.sync.copy(
                meta = if (meta != null) s.sync.meta + (id to meta.copy(isDirty = false, updatedAt = Instant.EPOCH)) else s.sync.meta,
                tombstones = s.sync.tombstones.filter { it.id != id },
                outbox = s.sync.outbox.filter { it.entityId != id },
                cursors = s.sync.cursors - entry.entity,
            ),
        )
    }

    private fun flagConflict(s: CareState, entity: SyncEntity, id: UUID, local: String, remote: String): CareState {
        val existing = s.sync.entry(id) ?: OutboxEntry(entity, id, createdAt = clock())
        // Never overwritten with nothing: a second pull must not erase what the first one captured.
        val flagged = existing.copy(
            status = OutboxStatus.NEEDS_REVIEW,
            lastError = "Someone else changed this while you were offline.",
            localSummary = local.ifEmpty { existing.localSummary },
            remoteSummary = remote.ifEmpty { existing.remoteSummary },
        )
        val outbox = if (s.sync.entry(id) == null) s.sync.outbox + flagged else s.sync.outbox.map { if (it.entityId == id) flagged else it }
        return s.copy(sync = s.sync.copy(outbox = outbox))
    }

    private fun localSummary(s: CareState, entity: SyncEntity, id: UUID): String {
        if (s.sync.tombstone(id) != null) return "Deleted on this phone"
        return when (entity) {
            SyncEntity.PERSON -> s.person(id)?.displayLabel.orEmpty()
            SyncEntity.MEDICATION -> s.medications.firstOrNull { it.id == id }?.let(::describe).orEmpty()
            else -> ""
        }
    }

    private fun remoteSummary(entity: SyncEntity, row: JSONObject, deleted: Boolean): String {
        if (deleted) return "Deleted by someone in the family"
        return when (entity) {
            SyncEntity.PERSON -> row.optString("name")
            SyncEntity.MEDICATION -> describe(SyncWire.medication(row, null))
            else -> ""
        }
    }

    private fun personFor(s: CareState, entity: SyncEntity, id: UUID): Person? = when (entity) {
        SyncEntity.PERSON -> s.person(id)
        SyncEntity.MEDICATION -> s.medications.firstOrNull { it.id == id }?.let { s.person(it.personId) }
        SyncEntity.VISIT -> s.visits.firstOrNull { it.id == id }?.let { s.person(it.personId) }
        SyncEntity.EMERGENCY_CONTACT -> s.contacts.firstOrNull { it.id == id }?.let { s.person(it.personId) }
        SyncEntity.PROVIDER -> s.providers.firstOrNull { it.id == id }?.let { s.person(it.personId) }
        SyncEntity.DOSE_LOG -> null
    }

    private fun titleFor(s: CareState, entity: SyncEntity, id: UUID): String {
        val title = when (entity) {
            SyncEntity.PERSON -> s.person(id)?.displayLabel
            SyncEntity.MEDICATION -> s.medications.firstOrNull { it.id == id }?.displayName
            SyncEntity.VISIT -> s.visits.firstOrNull { it.id == id }?.displayTitle()
            SyncEntity.EMERGENCY_CONTACT -> s.contacts.firstOrNull { it.id == id }?.name
            SyncEntity.PROVIDER -> s.providers.firstOrNull { it.id == id }?.name
            SyncEntity.DOSE_LOG -> null
        }
        return title?.takeIf { it.isNotBlank() } ?: entity.label
    }

    companion object {
        const val MAX_ATTEMPTS = 6

        /** Strength and schedule, because those are what two people disagree about. */
        fun describe(m: Medication): String {
            val parts = mutableListOf(m.displayName)
            if (m.isAsNeeded) parts += "as needed" else m.scheduleLabel().takeIf { it.isNotEmpty() }?.let { parts += it }
            if (m.instructions.isNotEmpty()) parts += m.instructions
            return parts.joinToString(" · ")
        }
    }
}

/**
 * Removes a row the family deleted. A person takes everything hanging off
 * them, a medication its doses: the other phones' tombstone cascade, as the
 * SwiftData relationship rules do on iOS.
 */
fun removeLocally(s: CareState, entity: SyncEntity, id: UUID): CareState {
    val gone = mutableSetOf(id)
    val next = when (entity) {
        SyncEntity.PERSON -> {
            val medIds = s.medicationsOf(id).map { it.id }.toSet()
            gone += medIds
            gone += s.doses.filter { it.medicationId in medIds }.map { it.id }
            gone += s.visitsOf(id).map { it.id } + s.contacts.filter { it.personId == id }.map { it.id } +
                s.providers.filter { it.personId == id }.map { it.id }
            s.copy(
                people = s.people.filter { it.id != id },
                medications = s.medications.filter { it.personId != id },
                doses = s.doses.filter { it.medicationId !in medIds },
                visits = s.visits.filter { it.personId != id },
                contacts = s.contacts.filter { it.personId != id },
                providers = s.providers.filter { it.personId != id },
            )
        }
        SyncEntity.MEDICATION -> {
            gone += s.dosesOf(id).map { it.id }
            s.copy(medications = s.medications.filter { it.id != id }, doses = s.doses.filter { it.medicationId != id })
        }
        SyncEntity.DOSE_LOG -> s.copy(doses = s.doses.filter { it.id != id })
        SyncEntity.VISIT -> s.copy(visits = s.visits.filter { it.id != id })
        SyncEntity.EMERGENCY_CONTACT -> s.copy(contacts = s.contacts.filter { it.id != id })
        SyncEntity.PROVIDER -> s.copy(providers = s.providers.filter { it.id != id })
    }
    return next.copy(
        sync = next.sync.copy(
            meta = next.sync.meta - gone,
            outbox = next.sync.outbox.filter { it.entityId !in gone },
        ),
    )
}
