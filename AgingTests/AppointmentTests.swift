import Foundation
import SwiftData
import Testing

@testable import Aging

/// A visit dated ahead is an appointment. Everything here is about that one
/// rule holding in the four places it is read: the two lists, the daily screen,
/// the history, and the reminder the evening before.
@MainActor
struct AppointmentTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    @discardableResult
    private func visit(
        _ provider: String,
        on date: Date,
        for person: Person,
        in context: ModelContext
    ) -> Visit {
        let visit = Visit(date: date, provider: provider, person: person)
        context.insert(visit)
        return visit
    }

    // MARK: Splitting the list

    @Test func aVisitDatedAheadIsUpcomingAndOneDatedBehindIsNot() {
        let context = makeContext()
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)
        let now = at(2026, 9, 10, 12)

        let booked = visit("Dr. Patel", on: at(2026, 9, 24, 9, 30), for: person, in: context)
        let logged = visit("Dr. Chen", on: at(2026, 8, 3), for: person, in: context)

        #expect(booked.isUpcoming(asOf: now))
        #expect(!logged.isUpcoming(asOf: now))
        #expect(person.upcomingVisits(asOf: now).map(\.id) == [booked.id])
        #expect(person.pastVisits(asOf: now).map(\.id) == [logged.id])
    }

    @Test func upcomingIsSoonestFirstAndPastIsMostRecentFirst() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        let now = at(2026, 9, 10, 12)

        visit("Later", on: at(2026, 10, 1, 10), for: person, in: context)
        visit("Sooner", on: at(2026, 9, 12, 10), for: person, in: context)
        visit("Old", on: at(2026, 6, 1), for: person, in: context)
        visit("Recent", on: at(2026, 9, 1), for: person, in: context)

        #expect(person.upcomingVisits(asOf: now).map(\.provider) == ["Sooner", "Later"])
        #expect(person.pastVisits(asOf: now).map(\.provider) == ["Recent", "Old"])
    }

    @Test func aTombstonedAppointmentIsInNeitherList() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        let now = at(2026, 9, 10, 12)

        let cancelled = visit("Dr. Patel", on: at(2026, 9, 24, 9), for: person, in: context)
        cancelled.deletedAt = Date()

        #expect(person.upcomingVisits(asOf: now).isEmpty)
        #expect(person.pastVisits(asOf: now).isEmpty)
    }

    // MARK: What Today shows

    @Test func todayShowsTheWeekAheadAndNotTheMonthAhead() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        let now = at(2026, 9, 10, 12)

        visit("This week", on: at(2026, 9, 14, 9), for: person, in: context)
        visit("Next month", on: at(2026, 10, 14, 9), for: person, in: context)

        let due = person.appointmentsDue(within: 7, now: now, calendar: calendar)

        #expect(due.map(\.provider) == ["This week"])
    }

    @Test func anAppointmentLaterTodayStillCounts() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        let now = at(2026, 9, 10, 8)

        visit("Dr. Patel", on: at(2026, 9, 10, 15, 30), for: person, in: context)

        #expect(person.appointmentsDue(now: now, calendar: calendar).count == 1)
    }

    // MARK: Time of day

    @Test func onlySomethingStillToComeShowsATimeOfDay() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        let now = at(2026, 9, 10, 12)

        // The shape every visit logged before appointments existed has: a
        // date-only picker never zeroed the clock, so the row carries whatever
        // time of day it happened to be written up at.
        let writeUp = visit("Dr. Chen", on: at(2026, 8, 3, 17, 4), for: person, in: context)
        let booked = visit("Dr. Patel", on: at(2026, 9, 24, 9, 30), for: person, in: context)

        #expect(!writeUp.hasTimeOfDay(calendar: calendar, asOf: now))
        #expect(booked.hasTimeOfDay(calendar: calendar, asOf: now))
        #expect(!writeUp.dateLabel(calendar: calendar).contains("5:04"))
        #expect(booked.dateLabel(calendar: calendar).contains("9:30"))
    }

    @Test func aRowIsTitledByWhoeverOrWhateverItIsAbout() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        let now = at(2026, 9, 10, 12)

        let named = visit("Dr. Patel", on: at(2026, 9, 24, 9), for: person, in: context)
        let reasonOnly = visit("", on: at(2026, 9, 25, 9), for: person, in: context)
        reasonOnly.reason = "Cardiology review"
        let bare = visit("", on: at(2026, 9, 26, 9), for: person, in: context)

        #expect(named.displayTitle(asOf: now) == "Dr. Patel")
        #expect(reasonOnly.displayTitle(asOf: now) == "Cardiology review")
        #expect(bare.displayTitle(asOf: now) == "Appointment")
    }

    // MARK: History

    @Test func anAppointmentIsNotHistoryUntilItHappens() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        let now = at(2026, 9, 10, 12)

        let booked = visit("Dr. Patel", on: at(2026, 9, 24, 9), for: person, in: context)
        let logged = visit("Dr. Chen", on: at(2026, 8, 3), for: person, in: context)

        let entries = TimelineBuilder.build(
            personID: person.id, visits: [booked, logged], now: now
        )

        #expect(entries.count == 1)
        #expect(entries.first?.title.contains("Dr. Chen") == true)
    }

    // MARK: Reminders

    @Test func anAppointmentIsRemindedTheEveningBefore() {
        let context = makeContext()
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)
        let now = at(2026, 9, 10, 12)

        let booked = visit("Dr. Patel", on: at(2026, 9, 24, 9, 30), for: person, in: context)
        booked.specialty = "Cardiology"

        let specs = AppointmentReminderPlanner.requests(for: [person], on: now, calendar: calendar)

        #expect(specs.count == 1)
        #expect(specs.first?.dateComponents.day == 23)
        #expect(specs.first?.dateComponents.hour == AppointmentReminderPlanner.notificationHour)
        #expect(specs.first?.body.contains("Eleanor") == true)
        #expect(specs.first?.body.contains("Dr. Patel") == true)
        #expect(specs.first?.body.contains("9:30") == true)
    }

    @Test func anAppointmentWhoseEveningHasPassedIsNotScheduled() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        // Booked for 9am tomorrow, and it is already 9pm tonight: the trigger
        // would be dated in the past, which iOS drops.
        visit("Dr. Patel", on: at(2026, 9, 11, 9), for: person, in: context)
        let specs = AppointmentReminderPlanner.requests(
            for: [person], on: at(2026, 9, 10, 21), calendar: calendar
        )

        #expect(specs.isEmpty)
    }

    @Test func aVisitAlreadyBeenToIsNeverReminded() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        visit("Dr. Chen", on: at(2026, 8, 3), for: person, in: context)
        let specs = AppointmentReminderPlanner.requests(
            for: [person], on: at(2026, 9, 10, 12), calendar: calendar
        )

        #expect(specs.isEmpty)
    }

    @Test func theSoonestAppointmentsComeFirstSoTheBudgetKeepsTheRightOnes() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        let now = at(2026, 9, 10, 12)

        visit("Later", on: at(2026, 11, 1, 10), for: person, in: context)
        visit("Sooner", on: at(2026, 9, 18, 10), for: person, in: context)
        visit("Soonest", on: at(2026, 9, 12, 10), for: person, in: context)

        let specs = AppointmentReminderPlanner.requests(for: [person], on: now, calendar: calendar)

        #expect(specs.map(\.what) == ["Soonest", "Sooner", "Later"])
    }

    @Test func theReminderIdentifierIsDerivedFromTheAppointment() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        let now = at(2026, 9, 10, 12)

        let booked = visit("Dr. Patel", on: at(2026, 9, 24, 9, 30), for: person, in: context)

        // Same input, same identifier: this is what makes the diff in
        // `applyAppointments` settle instead of re-adding on every foreground.
        let first = AppointmentReminderPlanner.requests(for: [person], on: now, calendar: calendar)
        let second = AppointmentReminderPlanner.requests(for: [person], on: now, calendar: calendar)

        #expect(first.map(\.identifier) == second.map(\.identifier))
        #expect(first.first?.identifier.contains(booked.id.uuidString) == true)
        #expect(first.first?.identifier.hasPrefix(AppointmentReminderSpec.identifierPrefix) == true)
    }
}
