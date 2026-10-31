import Foundation
import SwiftData
import Testing

@testable import Aging

/// A dosage edited on two phones is meant to stop and ask a person, never to be
/// settled by whichever write happens to go up last. Only one queued write was
/// ever flagged, though, and a medication saved twice offline has two. The
/// other went up on the next cycle with this phone's copy and the family's
/// version was gone, with the conflict still sitting in Settings asking about
/// a choice that had already been made for it.
@Suite("A conflict waiting for a person is not pushed over")
struct ConflictHoldTests {

    private func makeEngine() -> SyncEngine {
        SyncEngine(modelContainer: CareModelStore.makeInMemoryContainer())
    }

    /// The dosage a sibling set after the edits on this phone were made.
    private func theirs(_ medicationID: UUID, personID: UUID, group: UUID) -> MedicationDTO {
        MedicationDTO(
            id: medicationID, group_id: group, care_recipient_id: personID,
            name: "Metformin", strength: "1000 mg", form: "tablet", purpose: "",
            prescriber: "", pharmacy: "", provider_id: nil, pharmacy_id: nil,
            instructions: "", schedule_minutes: [8 * 60], weekdays: [],
            is_as_needed: false, is_active: true, start_date: Date(), end_date: nil,
            tracks_refills: true, quantity_remaining: 30, units_per_dose: 1,
            refill_threshold_days: 7, last_filled_at: nil, updated_by_name: nil,
            updated_at: Date().addingTimeInterval(600), deleted_at: nil
        )
    }

    @Test("Two saves of one medication made offline do not push over the family's dosage")
    func aSecondQueuedEditIsNotPushedOverTheFlaggedOne() async throws {
        let engine = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let medicationID = try await engine.insertMedicationForTesting(
            name: "Metformin", personID: personID, groupID: group
        )
        // Saved twice while offline: two queue entries for one record.
        await engine.enqueue(entity: .medication, id: medicationID, groupID: group)
        await engine.enqueue(entity: .medication, id: medicationID, groupID: group)
        try await remote.seed([theirs(medicationID, personID: personID, group: group)])

        let outcome = await engine.sync(remote: remote, groupID: group)

        #expect(outcome.conflicts == 1)
        #expect(outcome.pushed == 0)
        let stored = try await remote.rows(MedicationDTO.self)
        #expect(stored.count == 1)
        #expect(stored.first?.strength == "1000 mg")
    }

    @Test("A save made while a conflict is waiting waits with it, and goes up on Keep mine")
    func aSaveAfterTheFlagWaitsForTheChoice() async throws {
        let engine = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let medicationID = try await engine.insertMedicationForTesting(
            name: "Metformin", personID: personID, groupID: group
        )
        await engine.enqueue(entity: .medication, id: medicationID, groupID: group)
        try await remote.seed([theirs(medicationID, personID: personID, group: group)])
        _ = await engine.sync(remote: remote, groupID: group)

        // The caregiver carries on and saves the medication again.
        await engine.enqueue(entity: .medication, id: medicationID, groupID: group)
        let held = await engine.sync(remote: remote, groupID: group)

        #expect(held.pushed == 0)
        #expect(await engine.conflictCount() == 1)
        #expect(try await remote.rows(MedicationDTO.self).first?.strength == "1000 mg")

        // Keep mine: both saves are the same copy and go up as one.
        await engine.resolveKeepingLocal(id: medicationID)
        let chosen = await engine.sync(remote: remote, groupID: group)

        #expect(chosen.pushed == 1)
        #expect(await engine.conflictCount() == 0)
        #expect(try await remote.rows(MedicationDTO.self).first?.strength == "")
    }

    @Test("A person's conflict does not hold the same person's check-in window")
    func aPersonConflictLeavesTheCheckInWindowAlone() async throws {
        let engine = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        try await engine.insertCheckInSettingsForTesting(
            personID: personID, groupID: group, startMinute: 9 * 60, endMinute: 21 * 60
        )
        // The window's queue entry is keyed on the person, so it shares an id
        // with the person's own. It is queued first.
        await engine.enqueue(entity: .checkInSettings, id: personID, groupID: group)
        await engine.enqueue(entity: .person, id: personID, groupID: group)
        try await remote.seed([PersonDTO(
            id: personID, group_id: group, linked_user_id: nil, name: "Mom",
            relationship: "Mom", birth_date: nil, blood_type: "", color_index: 0,
            allergies: ["Sulfa"], conditions: [], notes: "",
            surrogate_attested_at: nil, last_check_in_at: nil, created_by_name: "Sarah",
            updated_at: Date().addingTimeInterval(600), deleted_at: nil
        )])

        let outcome = await engine.sync(remote: remote, groupID: group)

        // The person is the conflict; the window is not, and goes up.
        #expect(outcome.conflicts == 1)
        let people = try await remote.rows(PersonDTO.self)
        #expect(people.first?.allergies == ["Sulfa"])
        let windows = try await remote.rows(CheckInSettingsDTO.self)
        #expect(windows.count == 1)
        #expect(windows.first?.window_start_minute == 9 * 60)
    }
}
