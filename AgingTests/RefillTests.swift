import Foundation
import SwiftData
import Testing

@testable import Aging

@MainActor
struct RefillTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    // MARK: Decrementing on hand

    @Test func loggingATakenDoseDecrementsByUnitsPerDose() {
        let med = Medication(name: "Metformin")
        med.tracksRefills = true
        med.quantityRemaining = 30
        med.unitsPerDose = 2

        med.decrementForDoseTaken()

        #expect(med.quantityRemaining == 28)
    }

    @Test func decrementRunsOnceEvenIfCalledFromTwoLogicalDoses() {
        let med = Medication(name: "Metformin")
        med.tracksRefills = true
        med.quantityRemaining = 30
        med.unitsPerDose = 1

        med.decrementForDoseTaken()
        #expect(med.quantityRemaining == 29)

        med.decrementForDoseTaken()
        #expect(med.quantityRemaining == 28)
    }

    @Test func correctingATakenDosePutsTheUnitsBack() {
        let med = Medication(name: "Metformin")
        med.tracksRefills = true
        med.quantityRemaining = 30
        med.unitsPerDose = 2

        med.decrementForDoseTaken()
        med.restoreForDoseUntaken()

        #expect(med.quantityRemaining == 30)
    }

    @Test func restoringNeverTurnsTrackingOnForAnUntrackedMedication() {
        let med = Medication(name: "Metformin")
        med.unitsPerDose = 2
        #expect(!med.tracksRefills)

        med.restoreForDoseUntaken()

        #expect(med.quantityRemaining == 0)
        #expect(med.daysRemaining == nil)
    }

    /// The bug this whole flag exists for. Taking the last dose used to make
    /// the medication indistinguishable from one that never tracked refills.
    @Test func aTrackedMedicationThatRunsOutStaysTracked() {
        let med = Medication(name: "Metformin")
        med.tracksRefills = true
        med.quantityRemaining = 1
        med.unitsPerDose = 1
        med.scheduleMinutes = [8 * 60]

        med.decrementForDoseTaken()

        #expect(med.quantityRemaining == 0)
        #expect(med.tracksRefills)
        #expect(med.isOutOfStock)
        // Zero days, not "no answer": this is exactly when Today has to show it.
        #expect(med.daysRemaining == 0)
    }

    @Test func undoingTheDoseThatEmptiedTheBottlePutsItBack() {
        let med = Medication(name: "Metformin")
        med.tracksRefills = true
        med.quantityRemaining = 1
        med.unitsPerDose = 1

        med.decrementForDoseTaken()
        #expect(med.quantityRemaining == 0)

        med.restoreForDoseUntaken()

        #expect(med.quantityRemaining == 1)
        #expect(!med.isOutOfStock)
    }

    @Test func anEmptyTrackedMedicationIsStillRunningLow() {
        let med = Medication(name: "Metformin")
        med.tracksRefills = true
        med.quantityRemaining = 0
        med.unitsPerDose = 1
        med.scheduleMinutes = [8 * 60]
        med.refillThresholdDays = 7

        #expect(med.daysRemaining == 0)
        #expect(med.daysRemaining.map { $0 <= Double(med.refillThresholdDays) } == true)
    }

    @Test func decrementNeverGoesNegative() {
        let med = Medication(name: "Metformin")
        med.tracksRefills = true
        med.quantityRemaining = 1
        med.unitsPerDose = 5

        med.decrementForDoseTaken()

        #expect(med.quantityRemaining == 0)
    }

    @Test func decrementIsANoOpWhenUntracked() {
        let med = Medication(name: "Metformin")
        #expect(!med.tracksRefills)
        #expect(med.quantityRemaining == 0)

        med.decrementForDoseTaken()

        #expect(med.quantityRemaining == 0)
    }

    // MARK: The one real bug: a synced dose must not double-decrement

    @Test func aDoseLogArrivingThroughSyncDoesNotDecrementQuantity() async throws {
        let container = CareModelStore.makeInMemoryContainer()
        let engine = SyncEngine(modelContainer: container)
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let medicationID = try await engine.insertMedicationForTesting(
            name: "Metformin", personID: personID, groupID: group,
            quantityRemaining: 30, unitsPerDose: 1
        )

        // This device already saw this dose taken elsewhere (a sibling's
        // phone) and is only pulling the record of it, not creating it.
        try await remote.seed([DoseLogDTO(
            id: UUID(), group_id: group, medication_id: medicationID,
            scheduled_at: Date(), recorded_at: Date(), status: "taken",
            recorded_by_name: "Sam", note: "", updated_at: Date(), deleted_at: nil
        )])

        _ = await engine.sync(remote: remote, groupID: group)

        let snapshot = try await engine.medicationSnapshotForTesting(id: medicationID)
        #expect(snapshot?.quantityRemaining == 30)
    }

    // MARK: daysRemaining

    @Test func daysRemainingIsNilWhenUntracked() {
        let med = Medication(name: "Aspirin")
        med.scheduleMinutes = [8 * 60]

        #expect(med.daysRemaining == nil)
    }

    @Test func daysRemainingIsNilWhenAsNeeded() {
        let med = Medication(name: "Acetaminophen")
        med.tracksRefills = true
        med.quantityRemaining = 30
        med.unitsPerDose = 1
        med.scheduleMinutes = [8 * 60]
        med.isAsNeeded = true

        #expect(med.daysRemaining == nil)
    }

    @Test func daysRemainingDividesOnHandByDailyDoseRate() {
        let med = Medication(name: "Metformin")
        med.tracksRefills = true
        med.quantityRemaining = 20
        med.unitsPerDose = 2
        med.scheduleMinutes = [8 * 60, 20 * 60]

        #expect(med.daysRemaining == 5)
    }

    @Test func weekdayLimitedScheduleStretchesDaysRemaining() {
        // Once a week (Mondays only), one tablet a dose.
        let med = Medication(name: "Alendronate")
        med.tracksRefills = true
        med.quantityRemaining = 8
        med.unitsPerDose = 1
        med.scheduleMinutes = [8 * 60]
        med.weekdays = [2]

        // 1 dose/week = 1/7 dose per day, so 8 tablets last 56 days, not 8.
        #expect(med.daysRemaining == 56)
    }
}

// MARK: - Test reach-ins

extension SyncEngine {
    struct MedicationSnapshot: Sendable {
        var id: UUID
        var quantityRemaining: Double
    }

    /// Inserts a medication directly, bypassing the normal editor flow, so a
    /// test can seed refill state without depending on any view.
    func insertMedicationForTesting(
        name: String, personID: UUID, groupID: UUID?,
        quantityRemaining: Double, unitsPerDose: Double = 1
    ) throws -> UUID {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == personID })
        guard let person = try modelContext.fetch(descriptor).first else {
            throw TestReachInError.personNotFound
        }
        let medication = Medication(name: name, person: person)
        medication.tracksRefills = quantityRemaining > 0
        medication.quantityRemaining = quantityRemaining
        medication.unitsPerDose = unitsPerDose
        medication.groupID = groupID
        medication.isDirty = true
        modelContext.insert(medication)
        try modelContext.save()
        return medication.id
    }

    func medicationSnapshotForTesting(id: UUID) throws -> MedicationSnapshot? {
        let descriptor = FetchDescriptor<Medication>(predicate: #Predicate { $0.id == id })
        guard let medication = try modelContext.fetch(descriptor).first else { return nil }
        return MedicationSnapshot(id: medication.id, quantityRemaining: medication.quantityRemaining)
    }
}

enum TestReachInError: Error {
    case personNotFound
}
