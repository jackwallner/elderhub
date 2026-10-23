package com.jackwallner.aging.data

import com.jackwallner.aging.model.CareState
import com.jackwallner.aging.model.SyncEntity
import java.util.UUID

/** Sign-out must not remove the only copy of a shared edit without consent. */
object SignOutProtection {
    suspend fun prepare(care: CareStore, sync: suspend () -> Unit): String? {
        if (pendingChanges(care.state).isEmpty()) return null
        sync()
        val remaining = pendingChanges(care.state)
        if (remaining.isEmpty()) return null
        return "These changes could not be synced: ${remaining.joinToString(", ")}. Signing out will permanently discard them from this phone. " +
            "Your family will not receive them. Cancel to keep them and stay signed in."
    }

    fun pendingChanges(state: CareState): List<String> {
        val pending = mutableMapOf<SyncEntity, MutableSet<UUID>>()
        fun include(entity: SyncEntity, id: UUID) { pending.getOrPut(entity) { mutableSetOf() }.add(id) }
        state.sync.outbox.forEach { include(it.entity, it.entityId) }
        state.sync.tombstones.forEach { include(it.entity, it.id) }
        val people = state.people.filter { it.groupId != null }.map { it.id }.toSet()
        val medications = state.medications.filter { it.personId in people }.map { it.id }.toSet()
        fun dirty(entity: SyncEntity, id: UUID) {
            if (state.sync.meta[id]?.isDirty == true) include(entity, id)
        }
        people.forEach { dirty(SyncEntity.PERSON, it) }
        medications.forEach { dirty(SyncEntity.MEDICATION, it) }
        state.providers.filter { it.personId in people }.forEach { dirty(SyncEntity.PROVIDER, it.id) }
        state.doses.filter { it.medicationId in medications }.forEach { dirty(SyncEntity.DOSE_LOG, it.id) }
        state.visits.filter { it.personId in people }.forEach { dirty(SyncEntity.VISIT, it.id) }
        state.contacts.filter { it.personId in people }.forEach { dirty(SyncEntity.EMERGENCY_CONTACT, it.id) }
        return SyncEntity.pullOrder.mapNotNull { entity ->
            val count = pending[entity]?.size ?: return@mapNotNull null
            val label = if (entity == SyncEntity.PERSON && count != 1) "people"
                else entity.label.lowercase() + if (count == 1) "" else "s"
            "$count $label"
        }
    }
}
