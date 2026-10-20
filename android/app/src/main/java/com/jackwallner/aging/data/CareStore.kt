package com.jackwallner.aging.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.aging.model.CareState
import com.jackwallner.aging.model.DoseLog
import com.jackwallner.aging.model.DoseSlot
import com.jackwallner.aging.model.DoseStatus
import com.jackwallner.aging.model.EmergencyContact
import com.jackwallner.aging.model.Medication
import com.jackwallner.aging.model.Person
import com.jackwallner.aging.model.Provider
import com.jackwallner.aging.model.Visit
import java.io.File
import java.time.Instant
import java.util.UUID

/** Where the state lives between launches. A file on the phone; memory in tests. */
interface CarePersistence {
    fun load(): String?
    fun save(text: String)
}

class FilePersistence(private val file: File) : CarePersistence {
    override fun load(): String? = file.takeIf { it.isFile }?.readText()

    override fun save(text: String) {
        val tmp = File(file.parentFile, "${file.name}.tmp")
        tmp.writeText(text)
        if (!tmp.renameTo(file)) {
            file.writeText(text)
            tmp.delete()
        }
    }
}

class MemoryPersistence(var text: String? = null) : CarePersistence {
    override fun load(): String? = text
    override fun save(text: String) { this.text = text }
}

/** Free tier is one care recipient. Plus adds more; helpers never pay. */
object PaidBoundary {
    const val FREE_PERSON_LIMIT = 1

    fun canAddPerson(isUnlocked: Boolean, peopleCount: Int): Boolean =
        isUnlocked || peopleCount < FREE_PERSON_LIMIT
}

/**
 * The SwiftData store of this port: every screen renders from here and every
 * write lands here first. Offline is the product, so nothing waits on a network.
 */
class CareStore(private val persistence: CarePersistence) {
    var state by mutableStateOf(load())
        private set

    private fun load(): CareState =
        persistence.load()?.let { runCatching { CareCodec.decode(it) }.getOrNull() } ?: CareState()

    fun update(transform: (CareState) -> CareState) {
        val next = transform(state)
        if (next == state) return
        state = next
        persistence.save(CareCodec.encode(next))
    }

    fun reset() = update { CareState() }

    // MARK: - People

    fun completeOnboarding(name: String, relationship: String, isSelf: Boolean, attested: Boolean, now: Instant = Instant.now()): Person {
        val person = Person(
            name = name.trim(), relationship = relationship.trim(), isSelf = isSelf,
            surrogateAttestedAt = if (attested && !isSelf) now else null,
        )
        update { it.copy(people = it.people + person, hasCompletedOnboarding = true) }
        return person
    }

    fun upsertPerson(person: Person) = update { s ->
        val exists = s.people.any { it.id == person.id }
        s.copy(people = if (exists) s.people.map { if (it.id == person.id) person else it } else s.people + person)
    }

    /** Deletes a person and everything recorded about them. */
    fun deletePerson(id: UUID) = update { s ->
        val medIds = s.medicationsOf(id).map { it.id }.toSet()
        s.copy(
            people = s.people.filter { it.id != id },
            medications = s.medications.filter { it.personId != id },
            doses = s.doses.filter { it.medicationId !in medIds },
            visits = s.visits.filter { it.personId != id },
            contacts = s.contacts.filter { it.personId != id },
            providers = s.providers.filter { it.personId != id },
        )
    }

    fun setCaregiverName(name: String) = update { it.copy(caregiverName = name.trim()) }

    // MARK: - Medications

    fun upsertMedication(med: Medication) = update { s ->
        val exists = s.medications.any { it.id == med.id }
        s.copy(medications = if (exists) s.medications.map { if (it.id == med.id) med else it } else s.medications + med)
    }

    fun deleteMedication(id: UUID) = update { s ->
        s.copy(medications = s.medications.filter { it.id != id }, doses = s.doses.filter { it.medicationId != id })
    }

    /**
     * Logs a dose, reusing the slot's row when it was logged before. Refill
     * counts move only on a change into or out of `taken`, so a mistap never
     * loses a tablet.
     */
    fun recordDose(slot: DoseSlot, status: DoseStatus, now: Instant = Instant.now()) = update { s ->
        val id = DoseLog.deterministicId(slot.medicationId, slot.scheduledAt)
        val previous = s.doses.firstOrNull { it.id == id }
        val log = DoseLog(id, slot.medicationId, slot.scheduledAt, status, s.caregiverName, now, previous?.note.orEmpty())
        val wasTaken = previous?.status == DoseStatus.TAKEN
        val isTaken = status == DoseStatus.TAKEN
        s.copy(
            doses = s.doses.filter { it.id != id } + log,
            medications = s.medications.map { med ->
                when {
                    med.id != slot.medicationId -> med
                    isTaken && !wasTaken -> med.decrementedForDoseTaken()
                    wasTaken && !isTaken -> med.restoredForDoseUntaken()
                    else -> med
                }
            },
        )
    }

    /** Undo: the slot goes back to pending and a taken tablet goes back in the bottle. */
    fun clearDose(slot: DoseSlot) = update { s ->
        val id = DoseLog.deterministicId(slot.medicationId, slot.scheduledAt)
        val previous = s.doses.firstOrNull { it.id == id } ?: return@update s
        s.copy(
            doses = s.doses.filter { it.id != id },
            medications = s.medications.map { med ->
                if (med.id == slot.medicationId && previous.status == DoseStatus.TAKEN) med.restoredForDoseUntaken() else med
            },
        )
    }

    // MARK: - Visits, contacts, providers

    fun upsertVisit(visit: Visit) = update { s ->
        val exists = s.visits.any { it.id == visit.id }
        s.copy(visits = if (exists) s.visits.map { if (it.id == visit.id) visit else it } else s.visits + visit)
    }

    fun deleteVisit(id: UUID) = update { s -> s.copy(visits = s.visits.filter { it.id != id }) }

    /** Only one CALL FIRST per person: marking one primary clears the others. */
    fun upsertContact(contact: EmergencyContact) = update { s ->
        val exists = s.contacts.any { it.id == contact.id }
        val merged = if (exists) s.contacts.map { if (it.id == contact.id) contact else it } else s.contacts + contact
        s.copy(contacts = merged.map {
            if (contact.isPrimary && it.personId == contact.personId && it.id != contact.id) it.copy(isPrimary = false) else it
        })
    }

    fun deleteContact(id: UUID) = update { s -> s.copy(contacts = s.contacts.filter { it.id != id }) }

    fun upsertProvider(provider: Provider) = update { s ->
        val exists = s.providers.any { it.id == provider.id }
        s.copy(providers = if (exists) s.providers.map { if (it.id == provider.id) provider else it } else s.providers + provider)
    }

    /** Detaches the provider from every medication that points at it, then deletes it (iOS `detachAndTombstone`). */
    fun deleteProvider(id: UUID) = update { s ->
        s.copy(
            providers = s.providers.filter { it.id != id },
            medications = s.medications.map { med ->
                med.copy(providerId = med.providerId.takeIf { it != id }, pharmacyId = med.pharmacyId.takeIf { it != id })
            },
        )
    }
}
