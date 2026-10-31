import Foundation
import SwiftData
import Testing

@testable import Aging

/// A pull asks for everything after the cursor, and a cycle pulls before it
/// pushes. The cursor is written to the millisecond while Postgres keeps
/// microseconds, so the newest row of every table comes back on every cycle,
/// carrying a timestamp older than anything typed since.
///
/// Visits, vitals, contacts, providers, events, tasks, notes and bills already
/// keep an unsent edit that is newer than the copy arriving. These three did
/// not: they only asked "is the server's copy newer?" and, when it was not,
/// wrote it over the edit and cleared the dirty flag, so the push that
/// followed sent the old values back up. A new allergy, a taken dose's refill
/// count and a changed check-in window were all lost that way, silently.
@Suite("A newer unsent edit survives the older copy the server sends back")
struct PullKeepsLocalEditTests {

    private func makeEngine() -> SyncEngine {
        SyncEngine(modelContainer: CareModelStore.makeInMemoryContainer())
    }

    // MARK: Person

    @Test("An allergy typed offline is not replaced by the older copy of the person")
    func personEditSurvivesAnOlderServerRow() async throws {
        let engine = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        // Local: "Penicillin", edited just now and not yet sent.
        let id = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        await engine.enqueue(entity: .person, id: id, groupID: group)

        // Server: the copy from ten minutes ago, which is what comes back.
        try await remote.seed([PersonDTO(
            id: id, group_id: group, linked_user_id: nil, name: "Mom",
            relationship: "Mom", birth_date: nil, blood_type: "", color_index: 0,
            allergies: ["Sulfa"], conditions: [], notes: "",
            surrogate_attested_at: nil, last_check_in_at: nil, created_by_name: "Sarah",
            updated_at: Date().addingTimeInterval(-600), deleted_at: nil
        )])

        let outcome = await engine.sync(remote: remote, groupID: group)

        #expect(outcome.conflicts == 0)
        let people = try await engine.allPeopleForTesting()
        #expect(people.first?.allergies == ["Penicillin"])
        // And it is the edit, not the old copy, that goes up.
        let pushed = try await remote.rows(PersonDTO.self)
        #expect(pushed.first?.allergies == ["Penicillin"])
    }

    // MARK: Medication

    @Test("A dose taken offline keeps its tablet off the refill count")
    func medicationEditSurvivesAnOlderServerRow() async throws {
        let engine = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let medicationID = try await engine.insertMedicationForTesting(
            name: "Metformin", personID: personID, groupID: group
        )
        // 30 on hand became 28 when two doses were marked taken.
        try await engine.setQuantityOnHandForTesting(medicationID: medicationID, to: 28)
        await engine.enqueue(entity: .person, id: personID, groupID: group)
        await engine.enqueue(entity: .medication, id: medicationID, groupID: group)

        try await remote.seed([MedicationDTO(
            id: medicationID, group_id: group, care_recipient_id: personID,
            name: "Metformin", strength: "", form: "tablet", purpose: "",
            prescriber: "", pharmacy: "", provider_id: nil, pharmacy_id: nil,
            instructions: "", schedule_minutes: [8 * 60], weekdays: [],
            is_as_needed: false, is_active: true, start_date: Date(), end_date: nil,
            tracks_refills: true, quantity_remaining: 30, units_per_dose: 1,
            refill_threshold_days: 7, last_filled_at: nil, updated_by_name: nil,
            updated_at: Date().addingTimeInterval(-600), deleted_at: nil
        )])

        let outcome = await engine.sync(remote: remote, groupID: group)

        #expect(outcome.conflicts == 0)
        #expect(try await engine.medicationSnapshotForTesting(id: medicationID)?.quantityRemaining == 28)
        let pushed = try await remote.rows(MedicationDTO.self)
        #expect(pushed.first?.quantity_remaining == 28)
    }

    // MARK: Check-in window

    @Test("A check-in window changed on this phone is not put back by the older one")
    func checkInWindowSurvivesAnOlderServerRow() async throws {
        let engine = makeEngine()
        let remote = FakeRemote()
        let group = UUID()
        let personID = UUID()

        // The family moved the window to 9 to 9 just now; the server still
        // holds the 8 to 8 it was agreed as.
        try await engine.insertCheckInSettingsForTesting(
            personID: personID, groupID: group, startMinute: 9 * 60, endMinute: 21 * 60
        )
        await engine.enqueue(entity: .checkInSettings, id: personID, groupID: group)
        try await remote.seed([CheckInSettingsDTO(
            care_recipient_id: personID, group_id: group, enabled: true,
            window_start_minute: 8 * 60, window_end_minute: 20 * 60,
            grace_minutes: 60, timezone: "America/Los_Angeles",
            updated_at: Date().addingTimeInterval(-600)
        )])

        _ = await engine.sync(remote: remote, groupID: group)

        let window = try await engine.checkInWindowForTesting(personID: personID)
        #expect(window?.startMinute == 9 * 60)
        #expect(window?.endMinute == 21 * 60)
        let pushed = try await remote.rows(CheckInSettingsDTO.self)
        #expect(pushed.first?.window_start_minute == 9 * 60)
        #expect(pushed.first?.window_end_minute == 21 * 60)
    }

    @Test("A window pulled onto a phone that has none is written even when its clock is behind")
    func checkInWindowIsWrittenOnAPhoneWithNone() async throws {
        let engine = makeEngine()
        let remote = FakeRemote()
        let group = UUID()
        let personID = UUID()

        // A server stamp ahead of this phone's clock: a brand-new row, made
        // dirty and dated "now", used to be judged against it and skipped,
        // leaving the default window (off) in place of the agreed one.
        try await remote.seed([CheckInSettingsDTO(
            care_recipient_id: personID, group_id: group, enabled: true,
            window_start_minute: 10 * 60, window_end_minute: 22 * 60,
            grace_minutes: 30, timezone: "America/Los_Angeles",
            updated_at: Date().addingTimeInterval(3_600)
        )])

        _ = await engine.sync(remote: remote, groupID: group)

        let window = try await engine.checkInWindowForTesting(personID: personID)
        #expect(window?.enabled == true)
        #expect(window?.startMinute == 10 * 60)
        #expect(window?.endMinute == 22 * 60)
        #expect(window?.isDirty == false)
    }

    // MARK: A newer copy from the family is still taken

    @Test("A person edited on both sides is still flagged, not kept")
    func aNewerServerCopyStillWinsTheConflictRule() async throws {
        let engine = makeEngine()
        let remote = FakeRemote()
        let group = UUID()

        let id = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        await engine.enqueue(entity: .person, id: id, groupID: group)
        try await remote.seed([PersonDTO(
            id: id, group_id: group, linked_user_id: nil, name: "Mom",
            relationship: "Mom", birth_date: nil, blood_type: "", color_index: 0,
            allergies: ["Sulfa"], conditions: [], notes: "",
            surrogate_attested_at: nil, last_check_in_at: nil, created_by_name: "Sarah",
            updated_at: Date().addingTimeInterval(600), deleted_at: nil
        )])

        let outcome = await engine.sync(remote: remote, groupID: group)

        #expect(outcome.conflicts == 1)
        let people = try await engine.allPeopleForTesting()
        #expect(people.first?.allergies == ["Penicillin"])
    }
}

// MARK: - Test reach-ins

extension SyncEngine {
    /// What a tablet taken does to the medication row, without the view: the
    /// count drops, the row is dirty and dated now.
    func setQuantityOnHandForTesting(medicationID: UUID, to quantity: Double) throws {
        let descriptor = FetchDescriptor<Medication>(predicate: #Predicate { $0.id == medicationID })
        guard let medication = try modelContext.fetch(descriptor).first else {
            throw TestReachInError.personNotFound
        }
        medication.quantityRemaining = quantity
        medication.updatedAt = Date()
        medication.isDirty = true
        try modelContext.save()
    }

    struct CheckInWindowSnapshot: Sendable {
        var enabled: Bool
        var startMinute: Int
        var endMinute: Int
        var isDirty: Bool
    }

    /// A window the caregiver has just saved: enabled, dirty, dated now.
    func insertCheckInSettingsForTesting(
        personID: UUID, groupID: UUID?, startMinute: Int, endMinute: Int
    ) throws {
        let settings = CheckInSettings(personID: personID, groupID: groupID)
        settings.enabled = true
        settings.windowStartMinute = startMinute
        settings.windowEndMinute = endMinute
        settings.updatedAt = Date()
        settings.isDirty = true
        modelContext.insert(settings)
        try modelContext.save()
    }

    func checkInWindowForTesting(personID: UUID) throws -> CheckInWindowSnapshot? {
        let descriptor = FetchDescriptor<CheckInSettings>(predicate: #Predicate { $0.personID == personID })
        guard let settings = try modelContext.fetch(descriptor).first else { return nil }
        return CheckInWindowSnapshot(
            enabled: settings.enabled,
            startMinute: settings.windowStartMinute,
            endMinute: settings.windowEndMinute,
            isDirty: settings.isDirty
        )
    }
}
