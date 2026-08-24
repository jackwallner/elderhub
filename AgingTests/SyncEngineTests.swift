import Foundation
import SwiftData
import Testing

@testable import Aging

/// An in-memory stand-in for Postgres.
///
/// Cursor pagination, version conflicts and role-changed rejections are all
/// deterministic here and effectively untestable against a live backend, which
/// is the entire reason `SyncRemote` is a protocol.
actor FakeRemote: SyncRemote {
    private var storage: [String: [Data]] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Set to make the next push fail, standing in for a network drop or for
    /// RLS refusing a caregiver who was demoted while offline.
    var nextPushError: SyncError?
    /// The same, for a pull. Until this existed the fake's `pull` could not
    /// throw at all, which is how the worst defect in the codebase sat under
    /// 112 passing tests: the engine aborted the whole cycle on one failing
    /// table and nothing in the suite could express that.
    var nextPullError: SyncError?

    /// Tables this server does not have. A migration that was written, tested
    /// and never applied is exactly this, and it is what production served for
    /// two builds on `providers`, `care_events` and `care_tasks`.
    var missingTables: Set<String> = []

    /// Per-table column allow-list, checked on push. Nil means "accept
    /// anything", which was the old behaviour and the reason a client sending
    /// six columns the server had never heard of could not fail here.
    var knownColumns: [String: Set<String>] = [:]

    private(set) var pushCount = 0
    private(set) var pullCounts: [String: Int] = [:]

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func setNextPushError(_ error: SyncError?) { nextPushError = error }
    func setNextPullError(_ error: SyncError?) { nextPullError = error }
    func setMissingTables(_ tables: Set<String>) { missingTables = tables }
    func setKnownColumns(_ columns: Set<String>, for entity: SyncEntity) {
        knownColumns[entity.rawValue] = columns
    }
    func pullCount(_ entity: SyncEntity) -> Int { pullCounts[entity.rawValue] ?? 0 }

    func seed<T: SyncDTO>(_ rows: [T]) throws {
        var existing = storage[T.entity.rawValue] ?? []
        existing.append(contentsOf: try rows.map { try encoder.encode($0) })
        storage[T.entity.rawValue] = existing
    }

    func pull<T: SyncDTO>(_ type: T.Type, after page: SyncPage?, limit: Int) async throws -> [T] {
        pullCounts[T.entity.rawValue, default: 0] += 1
        if missingTables.contains(T.entity.rawValue) {
            throw SyncError.server(
                "Could not find the table 'public.\(T.entity.rawValue)' in the schema cache"
            )
        }
        if let error = nextPullError {
            nextPullError = nil
            throw error
        }
        let rows = try (storage[T.entity.rawValue] ?? []).map { try decoder.decode(T.self, from: $0) }
        let sorted = rows.sorted {
            let left = $0.updated_at ?? .distantPast
            let right = $1.updated_at ?? .distantPast
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
        let after = sorted.filter { row in
            guard let page else { return true }
            guard let updated = row.updated_at else { return false }
            if updated > page.updatedAt { return true }
            if updated == page.updatedAt { return row.id.uuidString > page.id.uuidString }
            return false
        }
        return Array(after.prefix(limit))
    }

    func push<T: SyncDTO>(_ rows: [T]) async throws {
        if missingTables.contains(T.entity.rawValue) {
            throw SyncError.server(
                "Could not find the table 'public.\(T.entity.rawValue)' in the schema cache"
            )
        }
        if let error = nextPushError {
            nextPushError = nil
            throw error
        }

        // PostgREST answers an upsert carrying a column the table does not have
        // with PGRST204. Without this the fake accepted anything, so the exact
        // shape of the shipped defect (a client sending `quantity_remaining` to
        // a table three migrations behind it) was unrepresentable in the suite.
        if let allowed = knownColumns[T.entity.rawValue] {
            for row in rows {
                let object = try JSONSerialization.jsonObject(with: try encoder.encode(row))
                let sent = Set((object as? [String: Any])?.keys.map { $0 } ?? [])
                if let unknown = sent.subtracting(allowed).sorted().first {
                    throw SyncError.server(
                        "Could not find the '\(unknown)' column of '\(T.entity.rawValue)' in the schema cache"
                    )
                }
            }
        }

        var existing = storage[T.entity.rawValue] ?? []
        let incoming = Set(rows.map(\.id))

        // The server's `dose_logs_dedupe_idx on (medication_id, scheduled_at)`.
        // Deduping only by `id`, as this fake used to, mirrors the client's own
        // former wrong assumption, so two devices logging the same dose could
        // not collide here however hard a test tried.
        for row in rows {
            guard let key = Self.dedupeKey(row) else { continue }
            let clash = try existing.contains { data in
                let stored = try decoder.decode(T.self, from: data)
                return Self.dedupeKey(stored) == key && !incoming.contains(stored.id)
            }
            if clash {
                throw SyncError.server(
                    "duplicate key value violates unique constraint \"dose_logs_dedupe_idx\""
                )
            }
        }

        pushCount += rows.count
        existing = try existing.filter { data in
            let row = try decoder.decode(T.self, from: data)
            return !incoming.contains(row.id)
        }
        existing.append(contentsOf: try rows.map { try encoder.encode($0) })
        storage[T.entity.rawValue] = existing
    }

    /// The natural key the server enforces uniqueness on, where there is one
    /// besides the primary key. Only dose logs have one.
    private static func dedupeKey<T: SyncDTO>(_ row: T) -> String? {
        guard let dose = row as? DoseLogDTO else { return nil }
        return "\(dose.medication_id.uuidString)|\(dose.scheduled_at.timeIntervalSince1970)"
    }

    func count(_ entity: SyncEntity) -> Int { (storage[entity.rawValue] ?? []).count }

    /// The pushed rows themselves, so a test can assert on `deleted_at` rather
    /// than only on how many rows arrived.
    func rows<T: SyncDTO>(_ type: T.Type) throws -> [T] {
        try (storage[T.entity.rawValue] ?? []).map { try decoder.decode(T.self, from: $0) }
    }
}

@Suite("Sync engine")
struct SyncEngineTests {

    private func makeEngine() -> (SyncEngine, ModelContainer) {
        let container = CareModelStore.makeInMemoryContainer()
        return (SyncEngine(modelContainer: container), container)
    }

    private func person(_ name: String, group: UUID, updated: Date) -> PersonDTO {
        PersonDTO(
            id: UUID(), group_id: group, linked_user_id: nil, name: name,
            relationship: "Mom", birth_date: nil, blood_type: "", color_index: 0,
            allergies: ["Penicillin"], conditions: [], notes: "",
            surrogate_attested_at: nil,
            last_check_in_at: nil, created_by_name: "Sarah",
            updated_at: updated, deleted_at: nil
        )
    }

    // MARK: - Pull

    @Test("A pulled recipient lands in the local store with their allergies")
    func pullCreatesLocalRows() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()
        try await remote.seed([person("Mom", group: group, updated: Date())])

        let outcome = await engine.sync(remote: remote, groupID: group)

        #expect(outcome.pulled == 1)
        #expect(outcome.wasOffline == false)

        let people = try await engine.allPeopleForTesting()
        #expect(people.count == 1)
        #expect(people.first?.allergies == ["Penicillin"])
    }

    @Test("The cursor advances so a second sync does not refetch everything")
    func cursorAdvances() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()
        try await remote.seed([
            person("Mom", group: group, updated: Date().addingTimeInterval(-60)),
            person("Dad", group: group, updated: Date())
        ])

        let first = await engine.sync(remote: remote, groupID: group)
        #expect(first.pulled == 2)

        // Nothing changed on the server, so the second pass must pull nothing.
        // If the cursor were not persisted this would return 2 again, and would
        // keep growing with every sync for the life of the install.
        let second = await engine.sync(remote: remote, groupID: group)
        #expect(second.pulled == 0)
    }

    @Test("Rows sharing a timestamp are not skipped at a page boundary")
    func compoundCursorHandlesTies() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()
        // Same instant, which is what a single server transaction produces.
        let sameMoment = Date()
        try await remote.seed([
            person("Mom", group: group, updated: sameMoment),
            person("Dad", group: group, updated: sameMoment),
            person("Aunt Rose", group: group, updated: sameMoment)
        ])

        let outcome = await engine.sync(remote: remote, groupID: group)
        #expect(outcome.pulled == 3)

        let people = try await engine.allPeopleForTesting()
        #expect(people.count == 3)
    }

    // MARK: - Push

    @Test("A local change reaches the server and stops being dirty")
    func pushSendsDirtyRows() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let id = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        await engine.enqueue(entity: .person, id: id, groupID: group)

        let outcome = await engine.sync(remote: remote, groupID: group)
        #expect(outcome.pushed == 1)
        #expect(await remote.count(.person) == 1)

        let people = try await engine.allPeopleForTesting()
        #expect(people.first?.isDirty == false)
    }

    @Test("Going offline mid-push keeps the work queued instead of dropping it")
    func offlinePushStaysQueued() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let id = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        await engine.enqueue(entity: .person, id: id, groupID: group)
        await remote.setNextPushError(.offline)

        let outcome = await engine.sync(remote: remote, groupID: group)
        #expect(outcome.wasOffline)
        #expect(outcome.pushed == 0)
        // Still queued, still dirty. Losing this row would lose a medication
        // someone entered at a bedside.
        #expect(await engine.outboxCountForTesting() == 1)
        #expect(await engine.conflictCount() == 0)

        // Network comes back.
        let retry = await engine.sync(remote: remote, groupID: group)
        #expect(retry.pushed == 1)
        #expect(await engine.outboxCountForTesting() == 0)
    }

    @Test("A demoted caregiver's queued edits stop and ask, rather than retrying forever")
    func rejectedPushNeedsReview() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let id = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        await engine.enqueue(entity: .person, id: id, groupID: group)
        await remote.setNextPushError(.rejected("row-level security"))

        let outcome = await engine.sync(remote: remote, groupID: group)
        #expect(outcome.needsReview == 1)
        #expect(await engine.conflictCount() == 1)

        // A later sync must not silently retry it: the answer will not change,
        // and quietly dropping a medication edit is worse than surfacing it.
        let later = await engine.sync(remote: remote, groupID: group)
        #expect(later.pushed == 0)
        #expect(await engine.conflictCount() == 1)
    }

    // MARK: - Providers (plan82 slice C)

    private func providerDTO(
        name: String, phone: String, recipientID: UUID, group: UUID, updated: Date
    ) -> ProviderDTO {
        ProviderDTO(
            id: UUID(), group_id: group, care_recipient_id: recipientID,
            name: name, specialty: "Cardiology", phone: phone, address: "",
            portal_url: "", notes: "", is_pharmacy: false,
            updated_at: updated, deleted_at: nil
        )
    }

    @Test("A provider pulled from the server lands in the local store")
    func providerPullCreatesLocalRow() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let dto = providerDTO(name: "Dr. Patel", phone: "555-0101", recipientID: personID, group: group, updated: Date())
        try await remote.seed([dto])

        let outcome = await engine.sync(remote: remote, groupID: group)
        #expect(outcome.pulled == 1)

        let snapshot = try await engine.providerSnapshotForTesting(id: dto.id)
        #expect(snapshot?.name == "Dr. Patel")
        #expect(snapshot?.phone == "555-0101")
    }

    @Test("A provider pushed from this device reaches the server and stops being dirty")
    func providerPushSendsDirtyRows() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let providerID = try await engine.insertProviderForTesting(name: "Dr. Patel", personID: personID, groupID: group)
        await engine.enqueue(entity: .provider, id: providerID, groupID: group)

        let outcome = await engine.sync(remote: remote, groupID: group)
        #expect(outcome.pushed == 1)
        #expect(await remote.count(.provider) == 1)

        let snapshot = try await engine.providerSnapshotForTesting(id: providerID)
        #expect(snapshot?.isDirty == false)
    }

    @Test("A provider edited on both sides resolves last-writer-wins, like emergency contacts")
    func providerConflictIsLastWriterWins() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let providerID = try await engine.insertProviderForTesting(name: "Dr. Patel", personID: personID, groupID: group)
        await engine.enqueue(entity: .provider, id: providerID, groupID: group)

        // A sibling changed the phone number on the server while this
        // device's edit was still queued, unsent.
        var theirs = providerDTO(
            name: "Dr. Patel", phone: "555-9999", recipientID: personID, group: group,
            updated: Date().addingTimeInterval(600)
        )
        theirs.id = providerID
        try await remote.seed([theirs])

        _ = await engine.sync(remote: remote, groupID: group)

        // Providers are a contact card, not a dosage: there is no conflict
        // flag, and the pulled row simply wins, same as `applyContact`.
        let snapshot = try await engine.providerSnapshotForTesting(id: providerID)
        #expect(snapshot?.phone == "555-9999")
        #expect(await engine.conflictCount() == 0)
    }

    // MARK: - Care events (plan82 slice D)

    private func careEventDTO(
        kind: CareEventKind, note: String, recordedByName: String,
        recipientID: UUID, group: UUID, updated: Date
    ) -> CareEventDTO {
        CareEventDTO(
            id: UUID(), group_id: group, care_recipient_id: recipientID,
            kind: kind.rawValue, occurred_at: Date(), severity: 0, note: note,
            recorded_by_name: recordedByName, updated_at: updated, deleted_at: nil
        )
    }

    @Test("A care event pulled from the server lands in the local store")
    func careEventPullCreatesLocalRow() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let dto = careEventDTO(
            kind: .fall, note: "Slipped in the kitchen", recordedByName: "Sarah",
            recipientID: personID, group: group, updated: Date()
        )
        try await remote.seed([dto])

        let outcome = await engine.sync(remote: remote, groupID: group)
        #expect(outcome.pulled == 1)

        let snapshot = try await engine.careEventSnapshotForTesting(id: dto.id)
        #expect(snapshot?.kindRaw == CareEventKind.fall.rawValue)
        #expect(snapshot?.recordedBy == "Sarah")
    }

    @Test("A care event pushed from this device reaches the server and stops being dirty")
    func careEventPushSendsDirtyRows() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let eventID = try await engine.insertCareEventForTesting(
            kind: .symptom, recordedBy: "Sarah", personID: personID, groupID: group
        )
        await engine.enqueue(entity: .careEvent, id: eventID, groupID: group)

        let outcome = await engine.sync(remote: remote, groupID: group)
        #expect(outcome.pushed == 1)
        #expect(await remote.count(.careEvent) == 1)

        let snapshot = try await engine.careEventSnapshotForTesting(id: eventID)
        #expect(snapshot?.isDirty == false)
    }

    @Test("A care event edited on both sides resolves last-writer-wins, like vitals")
    func careEventConflictIsLastWriterWins() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let eventID = try await engine.insertCareEventForTesting(
            kind: .fall, recordedBy: "Sarah", personID: personID, groupID: group
        )
        await engine.enqueue(entity: .careEvent, id: eventID, groupID: group)

        // A sibling edited the note on the server while this device's edit
        // was still queued, unsent.
        var theirs = careEventDTO(
            kind: .fall, note: "No injury, watched overnight", recordedByName: "Jack",
            recipientID: personID, group: group, updated: Date().addingTimeInterval(600)
        )
        theirs.id = eventID
        try await remote.seed([theirs])

        _ = await engine.sync(remote: remote, groupID: group)

        // A care event is a record, not a value two family members plausibly
        // fight over: there is no conflict flag, and the pulled row simply
        // wins, same as `applyVital`.
        let snapshot = try await engine.careEventSnapshotForTesting(id: eventID)
        #expect(snapshot?.note == "No injury, watched overnight")
        #expect(await engine.conflictCount() == 0)
    }

    // MARK: - Conflicts

    @Test("A dosage edited on both sides is flagged, never silently overwritten")
    func dosageConflictIsSurfaced() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        // Local edit that has not been pushed yet.
        let id = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        await engine.enqueue(entity: .person, id: id, groupID: group)

        // Meanwhile a sibling changed the same record, more recently.
        var theirs = person("Mom", group: group, updated: Date().addingTimeInterval(600))
        theirs.id = id
        theirs.allergies = ["Sulfa"]
        try await remote.seed([theirs])

        let outcome = await engine.sync(remote: remote, groupID: group)

        #expect(outcome.conflicts >= 1)
        // The local version survives untouched. Last-writer-wins on an allergy
        // list is the failure mode this whole branch exists to prevent.
        let people = try await engine.allPeopleForTesting()
        #expect(people.first?.allergies == ["Penicillin"])
    }

    @Test("Two edits to one record collapse, two doses never do")
    func coalescingRespectsEventLogs() async throws {
        #expect(SyncEntity.person.isCoalescable)
        #expect(SyncEntity.medication.isCoalescable)
        // Each dose and each check-in is a thing that happened. Merging two of
        // them would erase one from the record.
        #expect(SyncEntity.doseLog.isCoalescable == false)
        #expect(SyncEntity.checkIn.isCoalescable == false)
    }

    // MARK: - Cycle structure (plan84 §1.0)

    @Test("One table the server does not have cannot stop the other ten from arriving")
    func aMissingTableDoesNotAbortThePull() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        // `providers` is pulled second, and for two builds it did not exist in
        // production. The whole cycle used to throw out on it.
        await remote.setMissingTables([SyncEntity.provider.rawValue])
        try await remote.seed([person("Mom", group: group, updated: Date())])

        let outcome = await engine.sync(remote: remote, groupID: group)

        #expect(outcome.pulled == 1)
        // Every entity after the broken one was still asked for.
        #expect(await remote.pullCount(.medication) >= 1)
        #expect(await remote.pullCount(.checkInSettings) >= 1)
    }

    @Test("A queued dose still reaches the family when an unrelated table is broken")
    func aFailedPullDoesNotBlockThePush() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        await remote.setMissingTables([SyncEntity.provider.rawValue])
        let id = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        await engine.enqueue(entity: .person, id: id, groupID: group)

        let outcome = await engine.sync(remote: remote, groupID: group)

        // This is the shipped defect in one assertion. `pushOutbox` used to sit
        // inside the pull's `do` block, so a 404 on one table meant nothing
        // ever left the phone again, in either direction, for anyone.
        #expect(outcome.pushed == 1)
        #expect(await remote.count(.person) == 1)
    }

    @Test("A cycle that did not finish never reports itself as synced")
    func aFailedCycleIsNotComplete() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        await remote.setMissingTables([SyncEntity.provider.rawValue])
        let failed = await engine.sync(remote: remote, groupID: group)

        // The "Last synced: just now" that hid all of this keys off exactly
        // this flag. A `.server` failure is not `.offline`, and the old rule
        // only withheld the timestamp for `.offline`.
        #expect(failed.isComplete == false)
        #expect(failed.failure != nil)
        #expect(failed.wasOffline == false)

        await remote.setMissingTables([])
        let clean = await engine.sync(remote: remote, groupID: group)
        #expect(clean.isComplete)
        #expect(clean.failure == nil)
    }

    @Test("A column the server has never heard of is a visible failure, not a silent one")
    func anUnknownColumnFailsThePush() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        // The live `medications` table as it stood three migrations behind the
        // client: no refill columns, no provider links.
        await remote.setKnownColumns([
            "id", "group_id", "care_recipient_id", "name", "strength", "form",
            "purpose", "prescriber", "pharmacy", "instructions", "schedule_minutes",
            "weekdays", "is_as_needed", "is_active", "start_date", "end_date",
            "updated_by_name", "updated_at", "deleted_at"
        ], for: .medication)

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let medID = try await engine.insertMedicationForTesting(
            name: "Lisinopril", personID: personID, groupID: group
        )
        await engine.enqueue(entity: .medication, id: medID, groupID: group)

        let outcome = await engine.sync(remote: remote, groupID: group)

        #expect(outcome.pushed == 0)
        #expect(outcome.isComplete == false)
        #expect(outcome.failure?.contains("column") == true)
        // Retryable, not parked: a schema gap is fixed by a deploy, and asking
        // the family to "review" it would be asking them to fix a migration.
        #expect(await engine.outboxStatusesForTesting() == ["retrying"])
        #expect(await engine.conflictCount() == 0)
    }

    // MARK: - Dose logs (plan84 §1.5)

    @Test("Two devices logging the same dose produce one row, not a stuck duplicate")
    func twoDevicesLoggingOneDoseCollapse() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let medID = try await engine.insertMedicationForTesting(
            name: "Lisinopril", personID: personID, groupID: group
        )
        let eightAM = Date(timeIntervalSince1970: 1_754_294_400)

        // A sibling already logged the 8am pill and it reached the server.
        let theirs = DoseLogDTO(
            id: DoseLog.deterministicID(medicationID: medID, scheduledAt: eightAM),
            group_id: group, medication_id: medID, scheduled_at: eightAM,
            recorded_at: eightAM, status: "taken", recorded_by_name: "Sarah",
            note: "", updated_at: Date().addingTimeInterval(-600), deleted_at: nil
        )
        try await remote.seed([theirs])

        // This device logs it too, before pulling. Random ids gave two rows,
        // a 23505 against the server's dedupe index, and an outbox entry the
        // family was asked to "review" and could not resolve.
        let localID = try await engine.insertDoseLogForTesting(
            medicationID: medID, scheduledAt: eightAM, recordedBy: "Jack", groupID: group
        )
        #expect(localID == theirs.id)
        await engine.enqueue(entity: .doseLog, id: localID, groupID: group)

        let outcome = await engine.sync(remote: remote, groupID: group)

        #expect(outcome.isComplete)
        #expect(await engine.conflictCount() == 0)
        #expect(await remote.count(.doseLog) == 1)
        #expect(try await engine.doseLogCountForTesting() == 1)
    }

    @Test("The dose id is derived from the slot, so it is the same on every device")
    func doseLogIDIsStableAcrossDevices() {
        let medicationID = UUID()
        let slot = Date(timeIntervalSince1970: 1_754_294_400)

        #expect(
            DoseLog.deterministicID(medicationID: medicationID, scheduledAt: slot)
                == DoseLog.deterministicID(medicationID: medicationID, scheduledAt: slot)
        )
        // Same minute, different seconds: still the same dose. `ScheduleEngine`
        // already matches logs to slots at minute granularity.
        #expect(
            DoseLog.deterministicID(medicationID: medicationID, scheduledAt: slot)
                == DoseLog.deterministicID(medicationID: medicationID, scheduledAt: slot.addingTimeInterval(31))
        )
        #expect(
            DoseLog.deterministicID(medicationID: medicationID, scheduledAt: slot)
                != DoseLog.deterministicID(medicationID: medicationID, scheduledAt: slot.addingTimeInterval(3600))
        )
        #expect(
            DoseLog.deterministicID(medicationID: medicationID, scheduledAt: slot)
                != DoseLog.deterministicID(medicationID: UUID(), scheduledAt: slot)
        )
    }

    // MARK: - Visits and vitals are actually last-writer-wins (plan84 §1.5)

    @Test("A visit note typed a minute ago survives an older row arriving from the server")
    func aNewerLocalVisitEditIsNotClobbered() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let visitID = try await engine.insertVisitForTesting(
            reason: "Cardiology follow-up", notes: "Told to halve the lisinopril",
            personID: personID, groupID: group, updatedAt: Date()
        )
        await engine.enqueue(entity: .visit, id: visitID, groupID: group)

        // A row the sibling wrote ten minutes *before* this edit. Because a
        // cycle pulls before it pushes, the old code took it unconditionally
        // and the note vanished with no warning and no conflict prompt.
        var theirs = visitDTO(
            reason: "Cardiology", notes: "", recipientID: personID, group: group,
            updated: Date().addingTimeInterval(-600)
        )
        theirs.id = visitID
        try await remote.seed([theirs])

        _ = await engine.sync(remote: remote, groupID: group)

        let snapshot = try await engine.visitSnapshotForTesting(id: visitID)
        #expect(snapshot?.notes == "Told to halve the lisinopril")
        // Still LWW, so no conflict is raised for a human to resolve.
        #expect(await engine.conflictCount() == 0)
    }

    @Test("A genuinely newer visit from the family wins, which is what LWW means")
    func anOlderLocalVisitEditYields() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let visitID = try await engine.insertVisitForTesting(
            reason: "Cardiology", notes: "Old note",
            personID: personID, groupID: group, updatedAt: Date().addingTimeInterval(-600)
        )
        await engine.enqueue(entity: .visit, id: visitID, groupID: group)

        var theirs = visitDTO(
            reason: "Cardiology", notes: "Dose halved, recheck in six weeks",
            recipientID: personID, group: group, updated: Date()
        )
        theirs.id = visitID
        try await remote.seed([theirs])

        _ = await engine.sync(remote: remote, groupID: group)

        let snapshot = try await engine.visitSnapshotForTesting(id: visitID)
        #expect(snapshot?.notes == "Dose halved, recheck in six weeks")
        #expect(await engine.conflictCount() == 0)
    }

    @Test("A vital reading follows the same rule as a visit")
    func aNewerLocalVitalEditIsNotClobbered() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let vitalID = try await engine.insertVitalForTesting(
            primaryValue: 142, note: "Measured sitting, second cuff",
            personID: personID, groupID: group, updatedAt: Date()
        )
        await engine.enqueue(entity: .vital, id: vitalID, groupID: group)

        var theirs = vitalDTO(
            primaryValue: 118, note: "", recipientID: personID, group: group,
            updated: Date().addingTimeInterval(-600)
        )
        theirs.id = vitalID
        try await remote.seed([theirs])

        _ = await engine.sync(remote: remote, groupID: group)

        let snapshot = try await engine.vitalSnapshotForTesting(id: vitalID)
        #expect(snapshot?.primaryValue == 142)
        #expect(snapshot?.note == "Measured sitting, second cuff")
        #expect(await engine.conflictCount() == 0)
    }

    private func visitDTO(
        reason: String, notes: String, recipientID: UUID, group: UUID, updated: Date
    ) -> VisitDTO {
        VisitDTO(
            id: UUID(), group_id: group, care_recipient_id: recipientID,
            date: Date(), provider: "Dr. Patel", provider_id: nil, specialty: "Cardiology",
            reason: reason, notes: notes, follow_up: "", next_appointment: nil,
            updated_at: updated, deleted_at: nil
        )
    }

    private func vitalDTO(
        primaryValue: Double, note: String, recipientID: UUID, group: UUID, updated: Date
    ) -> VitalDTO {
        VitalDTO(
            id: UUID(), group_id: group, care_recipient_id: recipientID,
            kind: VitalKind.bloodPressure.rawValue, primary_value: primaryValue,
            secondary_value: 80, recorded_at: Date(), note: note,
            updated_at: updated, deleted_at: nil
        )
    }

    // MARK: - Children that arrive before their parent

    @Test("A visit whose person failed to arrive is not written attached to nobody")
    func aChildIsDeferredRatherThanOrphaned() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()
        SyncEngine.resetParentlessRepairFlagForTesting()

        // Exactly the shipped failure: `care_recipients` carried a bare date
        // that the decoder refused, the pull loop caught it per entity, and
        // `visits` landed anyway.
        let mom = person("Mom", group: group, updated: Date())
        try await remote.seed([mom])
        try await remote.seed([visitDTO(reason: "Cardiology", notes: "", recipientID: mom.id,
                                        group: group, updated: Date())])
        await remote.setMissingTables([SyncEntity.person.rawValue])

        _ = await engine.sync(remote: remote, groupID: group)

        // Nothing was written, rather than something invisible being written.
        #expect(try await engine.visitCountForTesting() == 0)

        // And the cursor did not step over it, so the next cycle is offered it
        // again. A high-water mark that moves past an unwritten row loses it.
        await remote.setMissingTables([])
        _ = await engine.sync(remote: remote, groupID: group)

        let visits = try await engine.visitParentsForTesting()
        #expect(visits.count == 1)
        #expect(visits.first??.uuidString == mom.id.uuidString)
    }

    @Test("A visit left behind by a deleted person is discarded, not waited on forever")
    func aChildOfADeletedPersonDoesNotStallItsTable() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()
        SyncEngine.resetParentlessRepairFlagForTesting()

        // Deleting a person tombstones them, and nothing cascades a tombstone
        // on the server, so their visits stay live rows pointing at a recipient
        // that will never be written locally. Waiting for that person is
        // waiting forever.
        var mom = person("Mom", group: group, updated: Date(timeIntervalSince1970: 1_000))
        mom.deleted_at = Date(timeIntervalSince1970: 1_500)
        let orphan = visitDTO(reason: "Cardiology", notes: "", recipientID: mom.id,
                              group: group, updated: Date(timeIntervalSince1970: 2_000))

        let dad = person("Dad", group: group, updated: Date(timeIntervalSince1970: 3_000))
        let live = visitDTO(reason: "Audiology", notes: "", recipientID: dad.id,
                            group: group, updated: Date(timeIntervalSince1970: 4_000))

        try await remote.seed([mom, dad])
        try await remote.seed([orphan, live])

        _ = await engine.sync(remote: remote, groupID: group)

        // The leftover row is dropped and the cursor steps over it, so Dad's
        // visit, which sorts after it, still arrives. Holding the page on the
        // orphan would have stopped this table for good.
        let parents = try await engine.visitParentsForTesting()
        #expect(parents.count == 1)
        #expect(parents.first??.uuidString == dad.id.uuidString)
    }

    @Test("A row an older build left attached to nobody is repaired, not left invisible")
    func aParentlessRowFromAnOlderBuildIsRepaired() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()
        SyncEngine.resetParentlessRepairFlagForTesting()

        let mom = person("Mom", group: group, updated: Date(timeIntervalSince1970: 1_000))
        let visit = visitDTO(reason: "Cardiology", notes: "Two stents",
                             recipientID: mom.id, group: group,
                             updated: Date(timeIntervalSince1970: 2_000))
        try await remote.seed([mom])
        try await remote.seed([visit])

        // The state build 27 left behind: the row is on the phone with no
        // person, and the cursor has already passed it, so nothing would ever
        // offer it again.
        try await engine.insertParentlessVisitForTesting(
            id: visit.id, groupID: group, updatedAt: visit.updated_at ?? Date()
        )
        await engine.setCursorForTesting(
            entity: .visit, updatedAt: visit.updated_at ?? Date(), id: visit.id
        )
        #expect(try await engine.visitParentsForTesting() == [UUID?.none])

        _ = await engine.sync(remote: remote, groupID: group)

        // One row still, now attached to the person it always belonged to.
        let parents = try await engine.visitParentsForTesting()
        #expect(parents.count == 1)
        #expect(parents.first??.uuidString == mom.id.uuidString)
    }

    @Test("The rewind runs once, and never on a store that has no parentless row")
    func theRepairDoesNotRewindAHealthyStore() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()
        SyncEngine.resetParentlessRepairFlagForTesting()

        let mom = person("Mom", group: group, updated: Date())
        try await remote.seed([mom])
        _ = await engine.sync(remote: remote, groupID: group)

        // A healthy store keeps the cursor it earned: the second cycle must not
        // re-download the record every time the app opens.
        let before = await engine.cursorIDForTesting(entity: .person)
        #expect(before == mom.id)
        _ = await engine.sync(remote: remote, groupID: group)
        #expect(await engine.cursorIDForTesting(entity: .person) == mom.id)
    }

    @Test("Adoption stamps a group onto local-only data and queues all of it")
    func adoptionQueuesEverything() async throws {
        let (engine, _) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        // Three people entered before the user ever made an account.
        for name in ["Mom", "Dad", "Me"] {
            _ = try await engine.insertPersonForTesting(name: name, groupID: nil)
        }

        await engine.adoptLocalData(into: group)
        let outcome = await engine.sync(remote: remote, groupID: group)

        #expect(outcome.pushed == 3)
        #expect(await remote.count(.person) == 3)

        let people = try await engine.allPeopleForTesting()
        #expect(people.allSatisfy { $0.groupID == group })
    }
}

// MARK: - Test reach-ins

extension SyncEngine {
    /// Snapshots, not `@Model` instances: those belong to this actor's context
    /// and are not `Sendable`.
    struct PersonSnapshot: Sendable {
        var id: UUID
        var name: String
        var allergies: [String]
        var isDirty: Bool
        var groupID: UUID?
    }

    func allPeopleForTesting() throws -> [PersonSnapshot] {
        try modelContext.fetch(FetchDescriptor<Person>()).map {
            PersonSnapshot(id: $0.id, name: $0.name, allergies: $0.allergies,
                           isDirty: $0.isDirty, groupID: $0.groupID)
        }
    }

    func insertPersonForTesting(name: String, groupID: UUID?) throws -> UUID {
        let person = Person(name: name, relationship: "Mom")
        person.allergies = ["Penicillin"]
        person.groupID = groupID
        person.isDirty = true
        modelContext.insert(person)
        try modelContext.save()
        return person.id
    }

    /// The one-time rewind is keyed in `UserDefaults`, which outlives a test.
    static func resetParentlessRepairFlagForTesting() {
        UserDefaults.standard.removeObject(forKey: "sync.repair.parentlessRows.v1")
    }

    func visitCountForTesting() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<Visit>())
    }

    /// The person id of every visit, `nil` where the row is attached to nobody.
    func visitParentsForTesting() throws -> [UUID?] {
        try modelContext.fetch(FetchDescriptor<Visit>()).map { $0.person?.id }
    }

    /// A visit exactly as build 27 wrote one: real row, real id, no person.
    func insertParentlessVisitForTesting(id: UUID, groupID: UUID, updatedAt: Date) throws {
        let visit = Visit(reason: "Cardiology")
        visit.id = id
        visit.groupID = groupID
        visit.updatedAt = updatedAt
        visit.isDirty = false
        modelContext.insert(visit)
        try modelContext.save()
    }

    func setCursorForTesting(entity: SyncEntity, updatedAt: Date, id: UUID) {
        setCursor(entity: entity, page: SyncPage(updatedAt: updatedAt, id: id))
        try? modelContext.save()
    }

    func cursorIDForTesting(entity: SyncEntity) -> UUID? {
        cursorPage(for: entity)?.id
    }

    func outboxCountForTesting() -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<OutboxEntry>())) ?? 0
    }

    /// Sorted, so a test can assert on *why* an entry is still queued rather
    /// than only that it is. `retrying` and `needsReview` are very different
    /// promises to the family.
    func outboxStatusesForTesting() -> [String] {
        ((try? modelContext.fetch(FetchDescriptor<OutboxEntry>())) ?? [])
            .map(\.statusRaw)
            .sorted()
    }

    // MARK: Medications, visits, vitals and doses (plan84 §1.5)

    func insertMedicationForTesting(name: String, personID: UUID, groupID: UUID?) throws -> UUID {
        let medication = Medication(name: name, person: try person(personID))
        medication.groupID = groupID
        medication.tracksRefills = true
        medication.quantityRemaining = 30
        medication.unitsPerDose = 1
        medication.isDirty = true
        modelContext.insert(medication)
        try modelContext.save()
        return medication.id
    }

    struct VisitSnapshot: Sendable {
        var id: UUID
        var reason: String
        var notes: String
        var isDirty: Bool
    }

    func insertVisitForTesting(
        reason: String, notes: String, personID: UUID, groupID: UUID?, updatedAt: Date
    ) throws -> UUID {
        let visit = Visit(reason: reason, person: try person(personID))
        visit.notes = notes
        visit.groupID = groupID
        visit.updatedAt = updatedAt
        visit.isDirty = true
        modelContext.insert(visit)
        try modelContext.save()
        return visit.id
    }

    func visitSnapshotForTesting(id: UUID) throws -> VisitSnapshot? {
        let descriptor = FetchDescriptor<Visit>(predicate: #Predicate { $0.id == id })
        guard let visit = try modelContext.fetch(descriptor).first else { return nil }
        return VisitSnapshot(id: visit.id, reason: visit.reason, notes: visit.notes, isDirty: visit.isDirty)
    }

    struct VitalSnapshot: Sendable {
        var id: UUID
        var primaryValue: Double
        var note: String
        var isDirty: Bool
    }

    func insertVitalForTesting(
        primaryValue: Double, note: String, personID: UUID, groupID: UUID?, updatedAt: Date
    ) throws -> UUID {
        let reading = VitalReading(kind: .bloodPressure, primaryValue: primaryValue,
                                   secondaryValue: 90, person: try person(personID))
        reading.note = note
        reading.groupID = groupID
        reading.updatedAt = updatedAt
        reading.isDirty = true
        modelContext.insert(reading)
        try modelContext.save()
        return reading.id
    }

    func vitalSnapshotForTesting(id: UUID) throws -> VitalSnapshot? {
        let descriptor = FetchDescriptor<VitalReading>(predicate: #Predicate { $0.id == id })
        guard let reading = try modelContext.fetch(descriptor).first else { return nil }
        return VitalSnapshot(id: reading.id, primaryValue: reading.primaryValue,
                             note: reading.note, isDirty: reading.isDirty)
    }

    func insertDoseLogForTesting(
        medicationID: UUID, scheduledAt: Date, recordedBy: String, groupID: UUID?
    ) throws -> UUID {
        let descriptor = FetchDescriptor<Medication>(predicate: #Predicate { $0.id == medicationID })
        guard let medication = try modelContext.fetch(descriptor).first else {
            throw TestReachInError.personNotFound
        }
        let log = DoseLog(scheduledAt: scheduledAt, status: .taken,
                          recordedBy: recordedBy, medication: medication)
        log.groupID = groupID
        log.isDirty = true
        modelContext.insert(log)
        try modelContext.save()
        return log.id
    }

    func doseLogCountForTesting() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<DoseLog>())
    }

    private func person(_ id: UUID) throws -> Person {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })
        guard let person = try modelContext.fetch(descriptor).first else {
            throw TestReachInError.personNotFound
        }
        return person
    }

    // MARK: Providers (plan82 slice C)

    struct ProviderSnapshot: Sendable {
        var id: UUID
        var name: String
        var phone: String
        var isDirty: Bool
    }

    func insertProviderForTesting(name: String, personID: UUID, groupID: UUID?) throws -> UUID {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == personID })
        guard let person = try modelContext.fetch(descriptor).first else {
            throw TestReachInError.personNotFound
        }
        let provider = Provider(name: name, person: person)
        provider.groupID = groupID
        provider.isDirty = true
        modelContext.insert(provider)
        try modelContext.save()
        return provider.id
    }

    func providerSnapshotForTesting(id: UUID) throws -> ProviderSnapshot? {
        let descriptor = FetchDescriptor<Provider>(predicate: #Predicate { $0.id == id })
        guard let provider = try modelContext.fetch(descriptor).first else { return nil }
        return ProviderSnapshot(id: provider.id, name: provider.name, phone: provider.phone, isDirty: provider.isDirty)
    }

    // MARK: Care events (plan82 slice D)

    struct CareEventSnapshot: Sendable {
        var id: UUID
        var kindRaw: String
        var note: String
        var recordedBy: String
        var isDirty: Bool
    }

    func insertCareEventForTesting(
        kind: CareEventKind, recordedBy: String, personID: UUID, groupID: UUID?
    ) throws -> UUID {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == personID })
        guard let person = try modelContext.fetch(descriptor).first else {
            throw TestReachInError.personNotFound
        }
        let event = CareEvent(kind: kind, recordedBy: recordedBy, person: person)
        event.groupID = groupID
        event.isDirty = true
        modelContext.insert(event)
        try modelContext.save()
        return event.id
    }

    func careEventSnapshotForTesting(id: UUID) throws -> CareEventSnapshot? {
        let descriptor = FetchDescriptor<CareEvent>(predicate: #Predicate { $0.id == id })
        guard let event = try modelContext.fetch(descriptor).first else { return nil }
        return CareEventSnapshot(
            id: event.id, kindRaw: event.kindRaw, note: event.note,
            recordedBy: event.recordedBy, isDirty: event.isDirty
        )
    }
}
