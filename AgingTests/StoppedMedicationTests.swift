import Foundation
import SwiftData
import Testing

@testable import Aging

/// Stopping a medication, which until now had no representation in the app.
///
/// `isActive` and `endDate` were on the model, the Timeline already rendered a
/// "Medication stopped" entry from the end date, and nothing could set either:
/// the only way to clear a drug off the list was to delete it, which took every
/// dose ever logged against it and, in a shared circle, removed it for the
/// whole family.
@MainActor
struct StoppedMedicationTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    private func makeMedication(in context: ModelContext) -> (Person, Medication) {
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)
        let med = Medication(name: "Warfarin", strength: "3 mg", person: person)
        med.scheduleMinutes = [18 * 60]
        context.insert(med)
        return (person, med)
    }

    @Test func stoppingTakesItOffTheListAndKeepsItInTheRecord() {
        let context = makeContext()
        let (person, med) = makeMedication(in: context)

        med.stop(on: Date(timeIntervalSince1970: 1_780_000_000))

        #expect(person.activeMedications.isEmpty)
        #expect(person.stoppedMedications.map(\.id) == [med.id])
        #expect(person.liveMedications.count == 1)
        #expect(med.endDate != nil)
    }

    @Test func stoppingKeepsEveryDoseAlreadyRecorded() {
        let context = makeContext()
        let (_, med) = makeMedication(in: context)
        let log = DoseLog(
            scheduledAt: Date(timeIntervalSince1970: 1_779_000_000),
            status: .taken,
            medication: med
        )
        context.insert(log)

        med.stop()

        #expect(med.liveDoses.count == 1)
    }

    @Test func aStoppedMedicationIsOffTheOnePagerAndOffTheDayItWasScheduledFor() {
        let context = makeContext()
        let (person, med) = makeMedication(in: context)
        med.stop()

        let output = MedListExporter.plainText(for: person)
        let slots = ScheduleEngine.slots(for: person, on: Date())

        #expect(!output.contains("Warfarin"))
        #expect(output.contains("No active medications recorded."))
        #expect(slots.isEmpty)
    }

    @Test func aStoppedMedicationEarnsNoReminder() {
        let context = makeContext()
        let (person, med) = makeMedication(in: context)
        med.stop()

        let specs = DoseReminderPlanner.requests(for: [person])

        #expect(specs.isEmpty)
    }

    @Test func startingAgainClearsTheEndDateSoTheHistoryDoesNotClaimItStopped() {
        let context = makeContext()
        let (person, med) = makeMedication(in: context)
        med.stop()

        med.restart()

        #expect(person.activeMedications.map(\.id) == [med.id])
        #expect(person.stoppedMedications.isEmpty)
        #expect(med.endDate == nil)

        let entries = TimelineBuilder.build(personID: person.id, medications: [med])
        let stopped = entries.filter { $0.kind == .medicationStopped }
        #expect(stopped.isEmpty)
    }

    @Test func stoppingIsWhatPutsAMedicationStoppedEntryInTheHistory() {
        let context = makeContext()
        let (person, med) = makeMedication(in: context)
        let stoppedAt = Date(timeIntervalSince1970: 1_780_000_000)

        med.stop(on: stoppedAt)

        let entries = TimelineBuilder.build(personID: person.id, medications: [med])
        let stopped = entries.first { $0.kind == .medicationStopped }

        #expect(stopped != nil)
        #expect(stopped?.date == stoppedAt)
        #expect(stopped?.title.contains("Warfarin") == true)
    }
}
