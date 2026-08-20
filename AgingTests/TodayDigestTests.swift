import Foundation
import SwiftData
import Testing

@testable import Aging

/// The counting behind "what is left today, for everyone".
///
/// This is the logic that makes Elderhub Plus true rather than aspirational: a
/// caregiver looking after two parents has to be able to see that Dad's 8am
/// dose is unticked without first switching to Dad. The Today tab and the Care
/// tab both render this type, so a bug here shows up as two screens quietly
/// disagreeing about the same family.
@MainActor
struct TodayDigestTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    /// 9am today, so "before now" and "after now" are both expressible without
    /// the test drifting depending on when it runs.
    private var noon: Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    }

    private func minutes(_ hour: Int) -> Int { hour * 60 }

    @discardableResult
    private func addMedication(
        _ name: String,
        at hours: [Int],
        to person: Person,
        in context: ModelContext
    ) -> Medication {
        let medication = Medication(name: name, person: person)
        medication.scheduleMinutes = hours.map(minutes)
        context.insert(medication)
        return medication
    }

    // MARK: - Overdue is the number that matters

    @Test func aDoseWhoseTimeHasPassedAndIsUntickedIsOverdue() {
        let context = makeContext()
        let mom = Person(name: "Eleanor", relationship: "Mom")
        context.insert(mom)
        addMedication("Metformin", at: [8], to: mom, in: context)

        let digest = TodayDigest.build(for: [mom], on: noon)[0]

        #expect(digest.overdueSlots.count == 1)
        #expect(digest.upcomingSlots.isEmpty)
        #expect(digest.statusLine == "1 dose overdue")
    }

    @Test func aDoseLaterTodayIsDueAndNotOverdue() {
        let context = makeContext()
        let mom = Person(name: "Eleanor", relationship: "Mom")
        context.insert(mom)
        addMedication("Atorvastatin", at: [20], to: mom, in: context)

        let digest = TodayDigest.build(for: [mom], on: noon)[0]

        #expect(digest.overdueSlots.isEmpty)
        #expect(digest.upcomingSlots.count == 1)
        #expect(digest.statusLine == "1 dose due")
    }

    /// A skipped dose is an answered question, not an outstanding one. Counting
    /// it as overdue would leave a permanent unclearable warning on the row for
    /// every drug a family deliberately stopped giving that morning.
    @Test func aRecordedDoseIsNotOutstandingWhateverTheStatus() {
        let context = makeContext()
        let mom = Person(name: "Eleanor", relationship: "Mom")
        context.insert(mom)
        let medication = addMedication("Ramipril", at: [8], to: mom, in: context)

        let slot = ScheduleEngine.slots(for: mom, on: noon)[0]
        let log = DoseLog(scheduledAt: slot.scheduledAt, status: .skipped, medication: medication)
        context.insert(log)

        let digest = TodayDigest.build(for: [mom], on: noon)[0]

        #expect(digest.overdueSlots.isEmpty)
        #expect(digest.pendingSlots.isEmpty)
        #expect(digest.isClear)
        #expect(digest.statusLine == "Nothing due today")
    }

    // MARK: - The two silences

    /// The distinction the Care tab row lives or dies on. "Nothing due today"
    /// on a record with no medications in it at all would tell a caregiver
    /// their setup was finished and their morning was clear, when neither is
    /// true.
    @Test func anEmptyRecordDoesNotReadAsADayAlreadyDealtWith() {
        let context = makeContext()
        let dad = Person(name: "Arthur", relationship: "Dad")
        context.insert(dad)

        let digest = TodayDigest.build(for: [dad], on: noon)[0]

        #expect(digest.statusLine == "Nothing recorded yet")
        #expect(digest.hasNothingToShow)
    }

    @Test func aRecordWithMedicationsAllTickedReadsAsDone() {
        let context = makeContext()
        let dad = Person(name: "Arthur", relationship: "Dad")
        context.insert(dad)
        let medication = addMedication("Donepezil", at: [8], to: dad, in: context)
        let slot = ScheduleEngine.slots(for: dad, on: noon)[0]
        context.insert(DoseLog(scheduledAt: slot.scheduledAt, status: .taken, medication: medication))

        let digest = TodayDigest.build(for: [dad], on: noon)[0]

        #expect(digest.statusLine == "Nothing due today")
        #expect(!digest.hasNothingToShow)
    }

    // MARK: - Two people

    @Test func eachPersonIsCountedSeparately() {
        let context = makeContext()
        let mom = Person(name: "Eleanor", relationship: "Mom")
        let dad = Person(name: "Arthur", relationship: "Dad")
        context.insert(mom)
        context.insert(dad)
        addMedication("Metformin", at: [8], to: mom, in: context)
        addMedication("Warfarin", at: [7, 20], to: dad, in: context)

        let digests = TodayDigest.build(for: [mom, dad], on: noon)

        #expect(digests.count == 2)
        #expect(digests[0].overdueSlots.count == 1)
        #expect(digests[1].overdueSlots.count == 1)
        #expect(digests[1].upcomingSlots.count == 1)
    }

    /// The headline is the line that has to make someone open the app. It leads
    /// with overdue because that is the only number on the screen that means
    /// "this should already have happened".
    @Test func theHeadlineSumsAcrossEveryoneAndLeadsWithOverdue() {
        let context = makeContext()
        let mom = Person(name: "Eleanor", relationship: "Mom")
        let dad = Person(name: "Arthur", relationship: "Dad")
        context.insert(mom)
        context.insert(dad)
        addMedication("Metformin", at: [8], to: mom, in: context)
        addMedication("Warfarin", at: [7, 20], to: dad, in: context)

        let headline = TodayDigest.headline(for: TodayDigest.build(for: [mom, dad], on: noon))

        #expect(headline == "2 doses overdue · 1 dose due")
    }

    @Test func theHeadlineSaysNothingDueWhenThereIsNothing() {
        let context = makeContext()
        let mom = Person(name: "Eleanor", relationship: "Mom")
        context.insert(mom)

        #expect(TodayDigest.headline(for: TodayDigest.build(for: [mom], on: noon)) == "Nothing due today")
    }

    // MARK: - Tombstones

    /// Deleted rows live in the store until the outbox has pushed them, so
    /// every list in the app has to filter them out. A digest that did not
    /// would put a deleted parent back on the daily screen.
    @Test func aTombstonedPersonIsNotCounted() {
        let context = makeContext()
        let mom = Person(name: "Eleanor", relationship: "Mom")
        let dad = Person(name: "Arthur", relationship: "Dad")
        context.insert(mom)
        context.insert(dad)
        dad.deletedAt = Date()

        let digests = TodayDigest.build(for: [mom, dad], on: noon)

        #expect(digests.count == 1)
        #expect(digests[0].person.id == mom.id)
    }

    // MARK: - Tasks and appointments

    @Test func anOverdueTaskCountsTowardsTheStatusLine() {
        let context = makeContext()
        let mom = Person(name: "Eleanor", relationship: "Mom")
        context.insert(mom)
        let task = CareTask(title: "Reorder hearing aid batteries", dueAt: noon.addingTimeInterval(-86_400), person: mom)
        context.insert(task)

        let digest = TodayDigest.build(for: [mom], on: noon)[0]

        #expect(digest.tasksDue.count == 1)
        #expect(digest.statusLine == "1 task")
        #expect(!digest.isClear)
    }

    @Test func severalKindsOfWorkAreJoinedIntoOneLine() {
        let context = makeContext()
        let mom = Person(name: "Eleanor", relationship: "Mom")
        context.insert(mom)
        addMedication("Metformin", at: [8], to: mom, in: context)
        context.insert(CareTask(title: "Call the surgery", dueAt: noon, person: mom))

        let digest = TodayDigest.build(for: [mom], on: noon)[0]

        #expect(digest.statusLine == "1 dose overdue · 1 task")
    }

    // MARK: - Refills

    /// One rule for "running low", read by both screens. `TodayView` used to
    /// carry its own copy of this and the person row would have needed a
    /// second.
    @Test func onlyMedicationsTrackingRefillsCanRunLow() {
        let context = makeContext()
        let mom = Person(name: "Eleanor", relationship: "Mom")
        context.insert(mom)
        let tracked = addMedication("Metformin", at: [8], to: mom, in: context)
        tracked.tracksRefills = true
        tracked.quantityRemaining = 1
        tracked.unitsPerDose = 1

        let untracked = addMedication("Ramipril", at: [8], to: mom, in: context)
        untracked.quantityRemaining = 0

        let low = TodayDigest.runningLow(for: mom)

        #expect(low.count == 1)
        #expect(low[0].id == tracked.id)
    }
}
