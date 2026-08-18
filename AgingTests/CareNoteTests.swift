import Foundation
import SwiftData
import Testing

@testable import Aging

/// The free-form notes pile.
///
/// Almost nothing here is about the model, which is three fields. It is about
/// the two ways a bag of unstructured text fails a family: a row that renders
/// as a blank line, so the note cannot be found again, and an edit that never
/// leaves the phone or is silently overwritten by a sibling's.
@MainActor
@Suite("Care notes")
struct CareNoteTests {

    // MARK: - Finding a note again

    @Test("A note with no title falls back to the first line of the body")
    func untitledNoteBorrowsItsFirstLine() {
        let note = CareNote(body: "Gate code 4417\nSide door, spare key with Marta")
        #expect(note.displayTitle == "Gate code 4417")
    }

    @Test("A note with nothing in it still renders a row rather than a blank line")
    func emptyNoteHasAPlaceholderTitle() {
        let note = CareNote()
        #expect(note.displayTitle == "Untitled note")
        #expect(note.isEmpty)
    }

    /// A one-line note titled by its own body would otherwise print the same
    /// words twice in the row.
    @Test("The preview drops a body that only repeats the title")
    func previewSkipsADuplicateBody() {
        let note = CareNote(body: "Gate code 4417")
        #expect(note.displayTitle == "Gate code 4417")
        #expect(note.previewBody.isEmpty)

        let titled = CareNote(title: "Gate", body: "Gate code 4417")
        #expect(titled.previewBody == "Gate code 4417")
    }

    @Test("Pinned notes sort first, then the most recently edited")
    func pinnedFirstThenRecent() {
        let old = CareNote(title: "Old")
        old.updatedAt = Date(timeIntervalSince1970: 1_000)
        let recent = CareNote(title: "Recent")
        recent.updatedAt = Date(timeIntervalSince1970: 9_000)
        let pinned = CareNote(title: "Pinned", isPinned: true)
        pinned.updatedAt = Date(timeIntervalSince1970: 500)

        let sorted = CareNote.sorted([old, recent, pinned])
        #expect(sorted.map(\.title) == ["Pinned", "Recent", "Old"])
    }

    @Test("Tombstoned notes never reach the list")
    func liveNotesExcludeTombstones() throws {
        let container = CareModelStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let person = Person(name: "Mom")
        context.insert(person)

        let kept = CareNote(title: "Gate code", person: person)
        let deleted = CareNote(title: "Old pharmacy", person: person)
        deleted.deletedAt = Date()
        context.insert(kept)
        context.insert(deleted)
        try context.save()

        #expect(person.liveNotes.map(\.title) == ["Gate code"])
    }

    // MARK: - Reaching the family

    @Test("A note is pushed with its body and its pin")
    func notePushesItsContent() async throws {
        let container = CareModelStore.makeInMemoryContainer()
        let engine = SyncEngine(modelContainer: container)
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let noteID = try await engine.insertCareNoteForTesting(
            title: "Getting in", body: "Gate code 4417", personID: personID, groupID: group
        )
        await engine.enqueue(entity: .note, id: noteID, groupID: group)

        let outcome = await engine.sync(remote: remote, groupID: group)
        #expect(outcome.pushed == 1)

        let rows = try await remote.rows(CareNoteDTO.self)
        #expect(rows.count == 1)
        #expect(rows.first?.title == "Getting in")
        #expect(rows.first?.body == "Gate code 4417")
        #expect(rows.first?.deleted_at == nil)
    }

    @Test("A deleted note is pushed as a tombstone")
    func deletedNoteReachesTheFamily() async throws {
        let container = CareModelStore.makeInMemoryContainer()
        let engine = SyncEngine(modelContainer: container)
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let noteID = try await engine.insertCareNoteForTesting(
            title: "Old code", body: "", personID: personID, groupID: group
        )
        try await engine.tombstoneCareNoteForTesting(id: noteID)
        await engine.enqueue(entity: .note, id: noteID, groupID: group)

        _ = await engine.sync(remote: remote, groupID: group)

        let rows = try await remote.rows(CareNoteDTO.self)
        #expect(rows.first?.deleted_at != nil)
    }

    @Test("A pulled note lands with its person attached")
    func pulledNoteAttachesToItsPerson() async throws {
        let container = CareModelStore.makeInMemoryContainer()
        let engine = SyncEngine(modelContainer: container)
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let dto = CareNoteDTO(
            id: UUID(), group_id: group, care_recipient_id: personID,
            title: "From Sarah", body: "Pharmacy line, press 2 for refills",
            is_pinned: true, created_by_name: "Sarah",
            updated_at: Date(), deleted_at: nil
        )
        try await remote.seed([dto])

        _ = await engine.sync(remote: remote, groupID: group)

        let snapshot = try await engine.careNoteSnapshotForTesting(id: dto.id)
        #expect(snapshot?.title == "From Sarah")
        #expect(snapshot?.isPinned == true)
        #expect(snapshot?.personID == personID)
        #expect(snapshot?.isDirty == false)
    }

    /// The reason notes flag rather than merge. A note is one field end to end,
    /// so taking the server copy over an unsent local edit does not lose a
    /// detail, it loses everything the person typed.
    @Test("A sibling's edit over an unsent local one is flagged, not swallowed")
    func concurrentEditsGoToAHuman() async throws {
        let container = CareModelStore.makeInMemoryContainer()
        let engine = SyncEngine(modelContainer: container)
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let noteID = try await engine.insertCareNoteForTesting(
            title: "Gate", body: "Code 4417", personID: personID, groupID: group
        )

        // The server's copy is newer than the local edit that has not been sent.
        let serverCopy = CareNoteDTO(
            id: noteID, group_id: group, care_recipient_id: personID,
            title: "Gate", body: "Code changed to 9902", is_pinned: false,
            created_by_name: "Sarah",
            updated_at: Date().addingTimeInterval(600), deleted_at: nil
        )
        try await remote.seed([serverCopy])

        _ = await engine.sync(remote: remote, groupID: group)

        let snapshot = try await engine.careNoteSnapshotForTesting(id: noteID)
        #expect(snapshot?.body == "Code 4417")
        #expect(await engine.conflictCount() == 1)
    }
}

// MARK: - Reach-ins

extension SyncEngine {
    struct CareNoteSnapshot: Sendable {
        var id: UUID
        var title: String
        var body: String
        var isPinned: Bool
        var personID: UUID?
        var isDirty: Bool
    }

    func insertCareNoteForTesting(title: String, body: String, personID: UUID, groupID: UUID?) throws -> UUID {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == personID })
        guard let person = try modelContext.fetch(descriptor).first else {
            throw TestReachInError.personNotFound
        }
        let note = CareNote(title: title, body: body, person: person)
        note.groupID = groupID
        note.isDirty = true
        modelContext.insert(note)
        try modelContext.save()
        return note.id
    }

    func tombstoneCareNoteForTesting(id: UUID) throws {
        let descriptor = FetchDescriptor<CareNote>(predicate: #Predicate { $0.id == id })
        guard let note = try modelContext.fetch(descriptor).first else { return }
        note.deletedAt = Date()
        note.isDirty = true
        try modelContext.save()
    }

    func careNoteSnapshotForTesting(id: UUID) throws -> CareNoteSnapshot? {
        let descriptor = FetchDescriptor<CareNote>(predicate: #Predicate { $0.id == id })
        guard let note = try modelContext.fetch(descriptor).first else { return nil }
        return CareNoteSnapshot(
            id: note.id, title: note.title, body: note.body, isPinned: note.isPinned,
            personID: note.person?.id, isDirty: note.isDirty
        )
    }
}
