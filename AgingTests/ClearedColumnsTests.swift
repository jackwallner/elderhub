import Foundation
import SwiftData
import Testing

@testable import Aging

/// An upsert only writes the columns present in its body, and `Codable` leaves
/// a nil optional out of the JSON. So a field that was emptied on this phone
/// was never emptied on the server: the old value came back on the next pull
/// and replaced the change. Reopening a ticked-off task, marking a bill unpaid,
/// starting a stopped medication again and putting a dose back after an undo
/// all reverted a sync later, and on every other phone as well.
@Suite("A cleared field reaches the server as a null")
struct ClearedColumnsTests {

    // MARK: What is sent

    private func sent<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let object = try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any]
        return try #require(object)
    }

    @Test("A reopened task sends its completion, due date and assignee id as null")
    func reopenedTask() throws {
        let body = try sent(CareTaskDTO(
            id: UUID(), group_id: UUID(), care_recipient_id: UUID(), title: "Call the pharmacy",
            notes: "", due_at: nil, priority: "normal", recurrence: "never",
            assignee_user_id: nil, assignee_name: "", completed_at: nil,
            completed_by_name: "", created_by_name: "Sarah", updated_at: nil, deleted_at: nil
        ))

        #expect(body["completed_at"] is NSNull)
        #expect(body["due_at"] is NSNull)
        #expect(body["assignee_user_id"] is NSNull)
        // The server stamps these. Sending them empty would blank them.
        #expect(body["updated_at"] == nil)
        #expect(body["deleted_at"] == nil)
    }

    @Test("A bill marked unpaid sends paid_at and due_at as null")
    func unpaidBill() throws {
        let body = try sent(BillDTO(
            id: UUID(), group_id: UUID(), care_recipient_id: UUID(), payee: "Care home",
            amount: 100, notes: "", category: "care", recurrence: "monthly", due_at: nil,
            is_auto_pay: false, paid_at: nil, paid_by_name: "", created_by_name: "Sarah",
            updated_at: nil, deleted_at: nil
        ))

        #expect(body["paid_at"] is NSNull)
        #expect(body["due_at"] is NSNull)
    }

    @Test("A restarted medication sends its end date, provider links and fill date as null")
    func restartedMedication() throws {
        let body = try sent(MedicationDTO(
            id: UUID(), group_id: UUID(), care_recipient_id: UUID(), name: "Warfarin",
            strength: "5 mg", form: "tablet", purpose: "", prescriber: "", pharmacy: "",
            provider_id: nil, pharmacy_id: nil, instructions: "", schedule_minutes: [480],
            weekdays: [], is_as_needed: false, is_active: true, start_date: Date(),
            end_date: nil, tracks_refills: false, quantity_remaining: 0, units_per_dose: 1,
            refill_threshold_days: 7, last_filled_at: nil, updated_by_name: nil,
            updated_at: nil, deleted_at: nil
        ))

        #expect(body["end_date"] is NSNull)
        #expect(body["provider_id"] is NSNull)
        #expect(body["pharmacy_id"] is NSNull)
        #expect(body["last_filled_at"] is NSNull)
        #expect(body["updated_by_name"] == nil)
        #expect(body["updated_at"] == nil)
    }

    @Test("A dose put back after an undo sends deleted_at as null")
    func doseLogPutBack() throws {
        let body = try sent(DoseLogDTO(
            id: UUID(), group_id: UUID(), medication_id: UUID(), scheduled_at: Date(),
            recorded_at: Date(), status: "taken", recorded_by_name: "Sarah", note: "",
            updated_at: nil, deleted_at: nil
        ))

        #expect(body["deleted_at"] is NSNull)
    }

    @Test("A visit with no provider and a person with no birthday send them as null")
    func visitAndPerson() throws {
        let visit = try sent(VisitDTO(
            id: UUID(), group_id: UUID(), care_recipient_id: UUID(), date: Date(),
            provider: "", provider_id: nil, specialty: "", reason: "", notes: "",
            follow_up: "", next_appointment: nil, updated_at: nil, deleted_at: nil
        ))
        #expect(visit["provider_id"] is NSNull)

        let person = try sent(PersonDTO(
            id: UUID(), group_id: UUID(), linked_user_id: nil, name: "Mom", relationship: "Mom",
            birth_date: nil, blood_type: "", color_index: 0, allergies: [], conditions: [],
            notes: "", surrogate_attested_at: nil, last_check_in_at: nil, created_by_name: nil,
            updated_at: nil, deleted_at: nil
        ))
        #expect(person["birth_date"] is NSNull)
        // Set by the server (the account that accepted the invitation, the
        // attestation, the last press). A push must never blank them.
        #expect(person["linked_user_id"] == nil)
        #expect(person["surrogate_attested_at"] == nil)
        #expect(person["last_check_in_at"] == nil)
    }

    @Test("A value that is present is still sent as itself")
    func presentValuesAreSent() throws {
        let when = Date(timeIntervalSince1970: 1_760_000_000)
        let assignee = UUID()
        let body = try sent(CareTaskDTO(
            id: UUID(), group_id: UUID(), care_recipient_id: UUID(), title: "x", notes: "",
            due_at: when, priority: "normal", recurrence: "never", assignee_user_id: assignee,
            assignee_name: "", completed_at: when, completed_by_name: "", created_by_name: "",
            updated_at: nil, deleted_at: nil
        ))

        #expect(body["completed_at"] is String)
        #expect(body["due_at"] is String)
        #expect(body["assignee_user_id"] as? String == assignee.uuidString)
    }

    @Test("A row without the key, and a row with null, both read as empty")
    func emptyColumnsAreRead() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let id = UUID()
        let base = """
        "id":"\(id)","group_id":"\(UUID())","care_recipient_id":"\(UUID())","title":"t",\
        "notes":"","priority":"normal","recurrence":"never","assignee_name":"",\
        "completed_by_name":"","created_by_name":""
        """

        let withNull = try decoder.decode(CareTaskDTO.self, from: Data(
            "{\(base),\"completed_at\":null,\"due_at\":null,\"assignee_user_id\":null}".utf8
        ))
        let withoutKeys = try decoder.decode(CareTaskDTO.self, from: Data("{\(base)}".utf8))
        let withDate = try decoder.decode(CareTaskDTO.self, from: Data(
            "{\(base),\"completed_at\":\"2026-10-31T12:00:00Z\"}".utf8
        ))

        #expect(withNull.completed_at == nil)
        #expect(withoutKeys.completed_at == nil)
        #expect(withDate.completed_at != nil)
    }

    // MARK: What happens to it

    private func makeEngine() -> SyncEngine {
        SyncEngine(modelContainer: CareModelStore.makeInMemoryContainer())
    }

    @Test("A task reopened after it was ticked off is still open two syncs later")
    func aReopenedTaskStaysOpen() async throws {
        let engine = makeEngine()
        let remote = FakeRemote()
        await remote.setMergesColumns(true)
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let taskID = try await engine.insertCareTaskForTesting(
            title: "Call the pharmacy", personID: personID, groupID: group
        )
        // Ticked off, and the tick reaches the family.
        try await engine.setCareTaskDoneForTesting(id: taskID, done: true)
        await engine.enqueue(entity: .person, id: personID, groupID: group)
        await engine.enqueue(entity: .careTask, id: taskID, groupID: group)
        _ = await engine.sync(remote: remote, groupID: group)

        // Reopened from the Done list.
        try await engine.setCareTaskDoneForTesting(id: taskID, done: false)
        await engine.enqueue(entity: .careTask, id: taskID, groupID: group)
        _ = await engine.sync(remote: remote, groupID: group)
        _ = await engine.sync(remote: remote, groupID: group)

        let snapshot = try await engine.careTaskSnapshotForTesting(id: taskID)
        let task = try #require(snapshot)
        #expect(task.completedAt == nil)
        let stored = try await remote.rows(CareTaskDTO.self)
        #expect(stored.count == 1)
        #expect(stored.first?.completed_at == nil)
    }

    @Test("A stopped medication that is started again is still on the list two syncs later")
    func aRestartedMedicationStaysRestarted() async throws {
        let engine = makeEngine()
        let remote = FakeRemote()
        await remote.setMergesColumns(true)
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let medicationID = try await engine.insertMedicationForTesting(
            name: "Warfarin", personID: personID, groupID: group
        )
        // Stopped a month ago, and the stop reaches the family.
        try await engine.setMedicationStoppedForTesting(
            id: medicationID, stopped: true, on: Date().addingTimeInterval(-30 * 86_400)
        )
        await engine.enqueue(entity: .person, id: personID, groupID: group)
        await engine.enqueue(entity: .medication, id: medicationID, groupID: group)
        _ = await engine.sync(remote: remote, groupID: group)

        // Started again. `Medication.restart` empties the end date.
        try await engine.setMedicationStoppedForTesting(id: medicationID, stopped: false, on: Date())
        await engine.enqueue(entity: .medication, id: medicationID, groupID: group)
        _ = await engine.sync(remote: remote, groupID: group)
        _ = await engine.sync(remote: remote, groupID: group)

        // An end date left behind schedules it nowhere: `isScheduled` and the
        // reminder planner both stop at it.
        let snapshot = try await engine.medicationRunStateForTesting(id: medicationID)
        let state = try #require(snapshot)
        #expect(state.isActive)
        #expect(state.endDate == nil)
        let stored = try await remote.rows(MedicationDTO.self)
        #expect(stored.count == 1)
        #expect(stored.first?.end_date == nil)
    }

    @Test("A dose put back after an undo is still recorded two syncs later")
    func aDosePutBackAfterAnUndoStaysRecorded() async throws {
        let engine = makeEngine()
        let remote = FakeRemote()
        await remote.setMergesColumns(true)
        let group = UUID()
        let eightAM = Date(timeIntervalSince1970: 1_754_294_400)

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let medicationID = try await engine.insertMedicationForTesting(
            name: "Lisinopril", personID: personID, groupID: group
        )
        let doseID = try await engine.insertDoseLogForTesting(
            medicationID: medicationID, scheduledAt: eightAM, recordedBy: "Jack", groupID: group
        )
        await engine.enqueue(entity: .person, id: personID, groupID: group)
        await engine.enqueue(entity: .medication, id: medicationID, groupID: group)
        await engine.enqueue(entity: .doseLog, id: doseID, groupID: group)
        _ = await engine.sync(remote: remote, groupID: group)

        // Undone, and the undo reaches the family: the server row is
        // tombstoned and the phone's own copy is cleared out.
        try await engine.tombstoneDoseLogForTesting(id: doseID)
        await engine.enqueue(entity: .doseLog, id: doseID, groupID: group)
        _ = await engine.sync(remote: remote, groupID: group)
        #expect(try await engine.doseLogCountForTesting() == 0)

        // Taken again for the same slot. The id is derived from the slot, so
        // it is the row the tombstone still holds on the server.
        let againID = try await engine.insertDoseLogForTesting(
            medicationID: medicationID, scheduledAt: eightAM, recordedBy: "Jack", groupID: group
        )
        #expect(againID == doseID)
        await engine.enqueue(entity: .doseLog, id: againID, groupID: group)
        _ = await engine.sync(remote: remote, groupID: group)
        _ = await engine.sync(remote: remote, groupID: group)

        #expect(try await engine.doseLogCountForTesting() == 1)
        let stored = try await remote.rows(DoseLogDTO.self)
        #expect(stored.count == 1)
        #expect(stored.first?.deleted_at == nil)
    }
}

// MARK: - Test reach-ins

extension SyncEngine {
    /// What ticking a task off, or reopening it, does to the row: the same
    /// fields `CareTask.markComplete` and `markIncomplete` set, minus the
    /// main-actor coordinator.
    func setCareTaskDoneForTesting(id: UUID, done: Bool) throws {
        let descriptor = FetchDescriptor<CareTask>(predicate: #Predicate { $0.id == id })
        guard let task = try modelContext.fetch(descriptor).first else {
            throw TestReachInError.personNotFound
        }
        task.completedAt = done ? Date() : nil
        task.completedByName = done ? "Sarah" : ""
        task.updatedAt = Date()
        task.isDirty = true
        try modelContext.save()
    }

    /// `Medication.stop(on:)` and `restart()`, which is what the editor's
    /// Stopped switch calls.
    func setMedicationStoppedForTesting(id: UUID, stopped: Bool, on date: Date) throws {
        let descriptor = FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })
        guard let medication = try modelContext.fetch(descriptor).first else {
            throw TestReachInError.personNotFound
        }
        if stopped {
            medication.stop(on: date)
        } else {
            medication.restart()
        }
        medication.updatedAt = Date()
        medication.isDirty = true
        try modelContext.save()
    }

    struct MedicationRunState: Sendable {
        var isActive: Bool
        var endDate: Date?
    }

    func medicationRunStateForTesting(id: UUID) throws -> MedicationRunState? {
        let descriptor = FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })
        guard let medication = try modelContext.fetch(descriptor).first else { return nil }
        return MedicationRunState(isActive: medication.isActive, endDate: medication.endDate)
    }

    /// Undoing a dose: the log is tombstoned, as `TodayView.clear` does.
    func tombstoneDoseLogForTesting(id: UUID) throws {
        let descriptor = FetchDescriptor<DoseLog>(predicate: #Predicate { $0.id == id })
        guard let log = try modelContext.fetch(descriptor).first else {
            throw TestReachInError.personNotFound
        }
        log.deletedAt = Date()
        log.updatedAt = Date()
        log.isDirty = true
        try modelContext.save()
    }
}
