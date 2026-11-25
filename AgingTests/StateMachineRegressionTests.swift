import Foundation
import SwiftData
import Testing

@testable import Aging

/// Regression tests for project-docs/audits/state-machines-2026-11-24.md.
@MainActor
struct StateMachineRegressionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// One tablet a day, warn at 7 days left, `quantity` on hand.
    private func trackedPerson(quantity: Double, in context: ModelContext) -> Person {
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)
        let med = Medication(name: "Metformin", strength: "500 mg", person: person)
        med.scheduleMinutes = [20 * 60]
        med.tracksRefills = true
        med.quantityRemaining = quantity
        med.unitsPerDose = 1
        med.refillThresholdDays = 7
        context.insert(med)
        return person
    }

    private func fireDate(_ spec: RefillReminderSpec?) -> Date? {
        spec.flatMap { calendar.date(from: $0.dateComponents) }
    }

    // MARK: M1, a refill reminder planned after 9:00 on its day

    /// The 8pm dose brings the supply to its threshold and the next refresh
    /// runs at 8:05pm. iOS used to be handed 9:00 this morning, a one-shot
    /// trigger already past that never fires.
    @Test func m1ARefillReminderPlannedAfterNineFiresAtTheNextNine() {
        let context = ModelContext(CareModelStore.makeInMemoryContainer())
        let person = trackedPerson(quantity: 7, in: context)
        let now = at(2026, 11, 24, 20, 5)
        #expect(person.liveMedications.first?.daysRemaining == 7)

        let specs = RefillReminderPlanner.requests(for: [person], on: now, calendar: calendar)
        #expect(specs.count == 1)
        #expect(fireDate(specs.first) == at(2026, 11, 25, 9, 0))
    }

    /// A supply already under its threshold, entered at lunch.
    @Test func m1ASupplyAlreadyLowWhenEnteredAtLunchIsStillReminded() {
        let context = ModelContext(CareModelStore.makeInMemoryContainer())
        let person = trackedPerson(quantity: 3, in: context)
        let now = at(2026, 11, 24, 12, 30)

        let fire = fireDate(RefillReminderPlanner.requests(for: [person], on: now, calendar: calendar).first)
        #expect(fire.map { $0 > now } == true)
        #expect(fire == at(2026, 11, 25, 9, 0))
    }

    /// The good request already pending for tomorrow 9:00 is left alone when
    /// the same evening replans, rather than replaced with a dead one.
    @Test func m1AnEveningReplanKeepsTheRequestAlreadyPending() {
        let context = ModelContext(CareModelStore.makeInMemoryContainer())
        let person = trackedPerson(quantity: 7, in: context)
        let first = RefillReminderPlanner.requests(for: [person], on: at(2026, 11, 24, 20, 5), calendar: calendar)
        let held = first.map {
            HeldReminder(identifier: $0.identifier, body: $0.body, dateComponents: $0.dateComponents)
        }

        let again = RefillReminderPlanner.requests(for: [person], on: at(2026, 11, 24, 22, 0), calendar: calendar)
        #expect(OneShotReminderDiff.toSchedule(again, held: held).isEmpty)
    }

    /// Control: planned before 9:00, the reminder still fires at 9:00 today.
    @Test func m1ControlPlannedBeforeNineFiresAtNineToday() {
        let context = ModelContext(CareModelStore.makeInMemoryContainer())
        let person = trackedPerson(quantity: 7, in: context)
        let specs = RefillReminderPlanner.requests(for: [person], on: at(2026, 11, 24, 7, 0), calendar: calendar)
        #expect(fireDate(specs.first) == at(2026, 11, 24, 9, 0))
    }

    /// Control: a threshold days away keeps its own day.
    @Test func m1ControlAThresholdDaysAwayKeepsItsDay() {
        let context = ModelContext(CareModelStore.makeInMemoryContainer())
        let person = trackedPerson(quantity: 10, in: context)
        let specs = RefillReminderPlanner.requests(for: [person], on: at(2026, 11, 24, 20, 5), calendar: calendar)
        #expect(fireDate(specs.first) == at(2026, 11, 27, 9, 0))
    }
}
