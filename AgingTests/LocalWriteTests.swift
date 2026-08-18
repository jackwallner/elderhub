import Foundation
import SwiftData
import Testing

@testable import Aging

/// The rules that make a local write actually leave the phone.
///
/// Every one of these covers a failure that is invisible on the device that
/// made the change: the row saves, the list updates, the screen looks right,
/// and the rest of the family never sees it. Deleting a discontinued
/// medication is the worst case, because the stale copy is the one that gets
/// read out in an emergency room.
@Suite("Local writes reach the family")
struct LocalWriteTests {

    // MARK: - Tombstones

    @Test("A deleted row is pushed as a tombstone, not dropped on the floor")
    func tombstoneReachesTheServer() async throws {
        let container = CareModelStore.makeInMemoryContainer()
        let engine = SyncEngine(modelContainer: container)
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let providerID = try await engine.insertProviderForTesting(
            name: "Dr. Patel", personID: personID, groupID: group
        )
        try await engine.tombstoneProviderForTesting(id: providerID)
        await engine.enqueue(entity: .provider, id: providerID, groupID: group)

        let outcome = await engine.sync(remote: remote, groupID: group)
        #expect(outcome.pushed == 1)

        // The row the server got has to carry the tombstone. Pushing it with a
        // null `deleted_at` would resurrect the provider on every other device.
        let rows = try await remote.rows(ProviderDTO.self)
        #expect(rows.count == 1)
        #expect(rows.first?.deleted_at != nil)
    }

    @Test("A pushed tombstone is then cleared out of the local store")
    func pushedTombstoneIsPurgedLocally() async throws {
        let container = CareModelStore.makeInMemoryContainer()
        let engine = SyncEngine(modelContainer: container)
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let providerID = try await engine.insertProviderForTesting(
            name: "Dr. Patel", personID: personID, groupID: group
        )
        try await engine.tombstoneProviderForTesting(id: providerID)
        await engine.enqueue(entity: .provider, id: providerID, groupID: group)

        _ = await engine.sync(remote: remote, groupID: group)

        // Kept only long enough for the push to read it. Keeping it forever
        // would grow the store with rows nothing renders.
        #expect(try await engine.providerSnapshotForTesting(id: providerID) == nil)
    }

    @Test("A tombstone that cannot be pushed yet survives to try again")
    func offlineTombstoneIsNotLostLocally() async throws {
        let container = CareModelStore.makeInMemoryContainer()
        let engine = SyncEngine(modelContainer: container)
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let providerID = try await engine.insertProviderForTesting(
            name: "Dr. Patel", personID: personID, groupID: group
        )
        try await engine.tombstoneProviderForTesting(id: providerID)
        await engine.enqueue(entity: .provider, id: providerID, groupID: group)
        await remote.setNextPushError(.offline)

        let offline = await engine.sync(remote: remote, groupID: group)
        #expect(offline.wasOffline)
        // Still here, because the retry has to have something to read. This is
        // the whole reason a delete is a tombstone and not a `context.delete`.
        #expect(try await engine.providerSnapshotForTesting(id: providerID) != nil)

        let retry = await engine.sync(remote: remote, groupID: group)
        #expect(retry.pushed == 1)
        #expect(try await remote.rows(ProviderDTO.self).first?.deleted_at != nil)
    }

    // MARK: - Reads skip tombstones

    @MainActor
    @Test("A tombstoned row is gone from every list before it has been pushed")
    func tombstonedRowsAreNotRendered() throws {
        let context = ModelContext(CareModelStore.makeInMemoryContainer())
        let person = Person(name: "Mom")
        context.insert(person)

        let keep = Medication(name: "Lisinopril", person: person)
        let drop = Medication(name: "Metformin", person: person)
        context.insert(keep)
        context.insert(drop)
        drop.deletedAt = Date()

        let visit = Visit(provider: "Dr. Patel", person: person)
        context.insert(visit)
        visit.deletedAt = Date()

        let contact = EmergencyContact(name: "Sarah", person: person)
        context.insert(contact)
        contact.deletedAt = Date()

        #expect(person.liveMedications.map(\.name) == ["Lisinopril"])
        #expect(person.activeMedications.map(\.name) == ["Lisinopril"])
        #expect(person.liveVisits.isEmpty)
        #expect(person.liveContacts.isEmpty)
    }

    // MARK: - Adoption

    @Test("Adoption carries visits, vitals, contacts and providers, not just medications")
    func adoptionCoversEveryTable() async throws {
        let container = CareModelStore.makeInMemoryContainer()
        let engine = SyncEngine(modelContainer: container)
        let remote = FakeRemote()
        let group = UUID()

        // Everything a local-only install can accumulate before anyone signs in.
        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: nil)
        _ = try await engine.insertMedicationForTesting(
            name: "Lisinopril", personID: personID, groupID: nil, quantityRemaining: 0
        )
        _ = try await engine.insertProviderForTesting(name: "Dr. Patel", personID: personID, groupID: nil)
        _ = try await engine.insertCareEventForTesting(
            kind: .fall, recordedBy: "Sarah", personID: personID, groupID: nil
        )
        try await engine.insertPersonChildrenForTesting(personID: personID)

        await engine.adoptLocalData(into: group)
        _ = await engine.sync(remote: remote, groupID: group)

        // A visit or an emergency contact left behind here is local forever:
        // nothing later marks it dirty, so the sibling who just joined never
        // sees it.
        #expect(await remote.count(.person) == 1)
        #expect(await remote.count(.medication) == 1)
        #expect(await remote.count(.provider) == 1)
        #expect(await remote.count(.careEvent) == 1)
        #expect(await remote.count(.visit) == 1)
        #expect(await remote.count(.vital) == 1)
        #expect(await remote.count(.emergencyContact) == 1)
    }
}

// MARK: - Test reach-ins

extension SyncEngine {
    func tombstoneProviderForTesting(id: UUID) throws {
        let descriptor = FetchDescriptor<Provider>(predicate: #Predicate { $0.id == id })
        guard let provider = try modelContext.fetch(descriptor).first else {
            throw TestReachInError.personNotFound
        }
        provider.deletedAt = Date()
        provider.isDirty = true
        try modelContext.save()
    }

    /// One visit, one vital and one contact, the three tables adoption used to
    /// walk straight past.
    func insertPersonChildrenForTesting(personID: UUID) throws {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == personID })
        guard let person = try modelContext.fetch(descriptor).first else {
            throw TestReachInError.personNotFound
        }
        modelContext.insert(Visit(provider: "Dr. Patel", person: person))
        modelContext.insert(VitalReading(kind: .weight, primaryValue: 148, person: person))
        modelContext.insert(EmergencyContact(name: "Sarah", person: person))
        try modelContext.save()
    }
}
