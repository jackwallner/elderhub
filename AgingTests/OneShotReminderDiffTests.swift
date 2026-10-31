import Foundation
import SwiftData
import Testing

@testable import Aging

/// A refill or an appointment reminder is keyed on the medication's or the
/// visit's id, and that id does not change when the date does. The diff only
/// asked whether the identifier was already pending, so moving an appointment
/// from the 24th to the 1st left iOS holding the old request: the reminder
/// still fired on the evening of the 23rd, about an appointment that had moved,
/// and nothing was ever scheduled for the evening of the 30th.
@MainActor
struct OneShotReminderDiffTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// What iOS would report for a request scheduled from this spec.
    private func held(_ spec: some OneShotReminderSpec) -> HeldReminder {
        HeldReminder(
            identifier: spec.identifier, body: spec.body, dateComponents: spec.dateComponents
        )
    }

    private func appointment(
        in context: ModelContext, on date: Date, provider: String = "Dr. Patel"
    ) -> (Person, Visit) {
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)
        let visit = Visit(date: date, provider: provider, person: person)
        context.insert(visit)
        return (person, visit)
    }

    private func trackedMedication(in context: ModelContext, quantity: Double) -> (Person, Medication) {
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)
        let med = Medication(name: "Metformin", strength: "500 mg", person: person)
        med.scheduleMinutes = [8 * 60]
        med.tracksRefills = true
        med.quantityRemaining = quantity
        med.unitsPerDose = 1
        med.refillThresholdDays = 7
        context.insert(med)
        return (person, med)
    }

    // MARK: Appointments

    @Test func aRescheduledAppointmentIsWrittenAgain() {
        let context = makeContext()
        let now = at(2026, 9, 10)
        let (person, visit) = appointment(in: context, on: at(2026, 9, 24, 9, 30))

        let pending = AppointmentReminderPlanner.requests(for: [person], on: now, calendar: calendar)
            .map { held($0) }

        visit.date = at(2026, 10, 1, 14, 0)
        let moved = AppointmentReminderPlanner.requests(for: [person], on: now, calendar: calendar)

        #expect(moved.count == 1)
        #expect(moved.map(\.identifier) == pending.map(\.identifier))
        #expect(OneShotReminderDiff.toSchedule(moved, held: pending).map(\.identifier) == moved.map(\.identifier))
    }

    @Test func anAppointmentWhoseTimeChangedOnTheSameDayIsWrittenAgain() {
        let context = makeContext()
        let now = at(2026, 9, 10)
        let (person, visit) = appointment(in: context, on: at(2026, 9, 24, 9, 30))

        let pending = AppointmentReminderPlanner.requests(for: [person], on: now, calendar: calendar)
            .map { held($0) }

        // Same evening, new wording: the lock screen would still say 9:30.
        visit.date = at(2026, 9, 24, 15, 45)
        let moved = AppointmentReminderPlanner.requests(for: [person], on: now, calendar: calendar)

        #expect(OneShotReminderDiff.toSchedule(moved, held: pending).count == 1)
    }

    @Test func anAppointmentThatHasNotChangedIsLeftAlone() {
        let context = makeContext()
        let now = at(2026, 9, 10)
        let (person, _) = appointment(in: context, on: at(2026, 9, 24, 9, 30))

        let specs = AppointmentReminderPlanner.requests(for: [person], on: now, calendar: calendar)

        #expect(OneShotReminderDiff.toSchedule(specs, held: specs.map { held($0) }).isEmpty)
    }

    // MARK: Refills

    @Test func aRefillReminderIsWrittenAgainWhenARefillMovesIt() {
        let context = makeContext()
        let now = at(2026, 9, 10)
        let (person, med) = trackedMedication(in: context, quantity: 30)

        let pending = RefillReminderPlanner.requests(for: [person], on: now, calendar: calendar)
            .map { held($0) }

        // A new bottle: the supply now runs out months later than it did.
        med.quantityRemaining = 90
        let refilled = RefillReminderPlanner.requests(for: [person], on: now, calendar: calendar)

        #expect(refilled.count == 1)
        #expect(refilled.map(\.identifier) == pending.map(\.identifier))
        #expect(OneShotReminderDiff.toSchedule(refilled, held: pending).count == 1)
    }

    @Test func aRefillReminderThatHasNotChangedIsLeftAlone() {
        let context = makeContext()
        let (person, _) = trackedMedication(in: context, quantity: 30)

        let specs = RefillReminderPlanner.requests(for: [person], on: at(2026, 9, 10), calendar: calendar)

        #expect(specs.count == 1)
        #expect(OneShotReminderDiff.toSchedule(specs, held: specs.map { held($0) }).isEmpty)
    }

    // MARK: Refills with a supply nobody could mean

    // The On hand and Units per dose fields take any number. Counting the days
    // to the refill forward from today turned that number into an Int, which
    // traps when it does not fit, and the planner runs on launch and on every
    // foreground: one mistyped quantity made an app that could not start.

    @Test func aSupplyTooLargeToCountDaysOfDoesNotCrashTheRefillPlanner() {
        let context = makeContext()
        let (person, _) = trackedMedication(in: context, quantity: 1e20)

        let specs = RefillReminderPlanner.requests(for: [person], on: at(2026, 9, 10), calendar: calendar)

        #expect(specs.isEmpty)
    }

    @Test func aDoseSizeSoSmallThatTheSupplyNeverEndsDoesNotCrashTheRefillPlanner() {
        let context = makeContext()
        let (person, med) = trackedMedication(in: context, quantity: 30)
        med.unitsPerDose = 1e-19

        let specs = RefillReminderPlanner.requests(for: [person], on: at(2026, 9, 10), calendar: calendar)

        #expect(specs.isEmpty)
    }

    @Test func aSupplyThatLastsMoreThanAYearStillGetsItsReminderOnTheRightDay() {
        let context = makeContext()
        // 400 days on hand, warned 7 days before the end: 393 days from the
        // 10th of September 2026 is the 8th of October 2027.
        let (person, _) = trackedMedication(in: context, quantity: 400)

        let specs = RefillReminderPlanner.requests(for: [person], on: at(2026, 9, 10), calendar: calendar)

        #expect(specs.count == 1)
        #expect(specs.first?.dateComponents.year == 2027)
        #expect(specs.first?.dateComponents.month == 10)
        #expect(specs.first?.dateComponents.day == 8)
        #expect(specs.first?.dateComponents.hour == RefillReminderPlanner.notificationHour)
    }

    // MARK: Either kind

    @Test func aReminderNobodyHoldsYetIsScheduled() {
        let context = makeContext()
        let (person, _) = appointment(in: context, on: at(2026, 9, 24, 9, 30))
        let specs = AppointmentReminderPlanner.requests(for: [person], on: at(2026, 9, 10), calendar: calendar)

        #expect(OneShotReminderDiff.toSchedule(specs, held: []).count == specs.count)
    }

    @Test func aRequestUnderAnotherIdentifierDoesNotCountAsHeld() {
        let context = makeContext()
        let (person, _) = appointment(in: context, on: at(2026, 9, 24, 9, 30))
        let specs = AppointmentReminderPlanner.requests(for: [person], on: at(2026, 9, 10), calendar: calendar)
        let other = HeldReminder(
            identifier: "appointment-\(UUID().uuidString)",
            body: specs[0].body,
            dateComponents: specs[0].dateComponents
        )

        #expect(OneShotReminderDiff.toSchedule(specs, held: [other]).count == 1)
    }
}
