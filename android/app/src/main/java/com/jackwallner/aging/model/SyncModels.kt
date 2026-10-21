package com.jackwallner.aging.model

import java.time.Instant
import java.util.UUID

/**
 * Port of `Shared/Models/SyncModels.swift`, limited to the tables the Android
 * record holds. Vitals, care events, tasks, notes, bills and check-in settings
 * are not pulled at all, so no cursor ever moves past their rows: the build
 * that ports one of them pulls it from the start.
 */
enum class SyncEntity(val table: String, val label: String) {
    PERSON("care_recipients", "Person"),
    PROVIDER("providers", "Provider"),
    MEDICATION("medications", "Medication"),
    DOSE_LOG("dose_logs", "Dose"),
    VISIT("visits", "Visit"),
    EMERGENCY_CONTACT("emergency_contacts", "Contact");

    companion object {
        /** Parents before children, so a medication never lands before the person it belongs to. */
        val pullOrder = listOf(PERSON, PROVIDER, MEDICATION, DOSE_LOG, VISIT, EMERGENCY_CONTACT)

        fun of(table: String): SyncEntity? = entries.firstOrNull { it.table == table }
    }
}

/** Strictly-after position in a table: the server's `updated_at`, ties broken by id. */
data class SyncPage(val updatedAt: Instant, val id: UUID)

/** When a row last changed and whether this phone still owes the server that change. */
data class RowMeta(val updatedAt: Instant, val isDirty: Boolean)

/**
 * A deleted row waiting to reach the family. The wire row is captured at the
 * moment of deletion because the live row is gone from the record by then, and
 * the push needs something to send (`SyncableRecord.tombstone` on iOS).
 */
data class Tombstone(val entity: SyncEntity, val id: UUID, val deletedAt: Instant, val payload: String)

enum class OutboxStatus(val raw: String) {
    PENDING("pending"), RETRYING("retrying"),

    /** Refused for a reason retrying cannot fix, or a real conflict. A person decides. */
    NEEDS_REVIEW("needsReview");

    companion object {
        fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: PENDING
    }
}

data class OutboxEntry(
    val entity: SyncEntity,
    val entityId: UUID,
    val createdAt: Instant = Instant.now(),
    val attempts: Int = 0,
    val status: OutboxStatus = OutboxStatus.PENDING,
    val lastError: String = "",
    val notBefore: Instant = Instant.EPOCH,
    /** Both readings of a conflicted row, captured when flagged: the pull discards the family's copy. */
    val localSummary: String = "",
    val remoteSummary: String = "",
)

/** Everything the sync engine keeps on the phone between cycles. */
data class SyncState(
    val meta: Map<UUID, RowMeta> = emptyMap(),
    val tombstones: List<Tombstone> = emptyList(),
    val outbox: List<OutboxEntry> = emptyList(),
    val cursors: Map<SyncEntity, SyncPage> = emptyMap(),
) {
    fun tombstone(id: UUID): Tombstone? = tombstones.firstOrNull { it.id == id }

    fun entry(id: UUID): OutboxEntry? = outbox.firstOrNull { it.entityId == id }

    val conflictCount: Int get() = outbox.count { it.status == OutboxStatus.NEEDS_REVIEW }

    val pendingCount: Int get() = outbox.count { it.status != OutboxStatus.NEEDS_REVIEW }
}
