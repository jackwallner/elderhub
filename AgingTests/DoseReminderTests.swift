import Foundation
import SwiftData
import Testing

@testable import Aging

@MainActor
struct DoseReminderTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    @discardableResult
    private func medication(
        _ name: String,
        for person: Person,
        in context: ModelContext,
        minutes: [Int] = [8 * 60],
        weekdays: [Int] = []
    ) -> Medication {
        let med = Medication(name: name, strength: "500 mg", person: person)
        med.scheduleMinutes = minutes
        med.weekdays = weekdays
        med.startDate = day(2026, 7, 1)
        context.insert(med)
        return med
    }

    // MARK: Weekdays

    @Test func emptyWeekdaysMeansOneSpecPerTimeEveryDay() {
        let context = makeContext()
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)
        medication("Metformin", for: person, in: context, minutes: [8 * 60, 19 * 60 + 30])

        let specs = DoseReminderPlanner.requests(for: [person], on: day(2026, 7, 15), calendar: calendar)
        let allEveryDay = specs.allSatisfy { $0.weekday == nil }
        let evening = specs.first(where: { $0.hour == 19 })

        #expect(specs.count == 2)
        #expect(allEveryDay)
        #expect(Set(specs.map(\.hour)) == [8, 19])
        #expect(evening?.minute == 30)
    }

    @Test func specificWeekdaysProduceOneSpecPerDay() {
        let context = makeContext()
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)
        // Monday and Thursday, twice a day.
        medication("Alendronate", for: person, in: context, minutes: [7 * 60, 20 * 60], weekdays: [2, 5])

        let specs = DoseReminderPlanner.requests(for: [person], on: day(2026, 7, 15), calendar: calendar)

        #expect(specs.count == 4)
        #expect(Set(specs.compactMap(\.weekday)) == [2, 5])
        #expect(Set(specs.map(\.identifier)).count == 4)
    }

    // MARK: Exclusions

    @Test func asNeededMedicationProducesNoSpecs() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        let med = medication("Acetaminophen", for: person, in: context)
        med.isAsNeeded = true

        #expect(DoseReminderPlanner.requests(for: [person], on: day(2026, 7, 15), calendar: calendar).isEmpty)
    }

    @Test func inactiveEndedAndDeletedMedicationsProduceNoSpecs() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let inactive = medication("Lisinopril", for: person, in: context)
        inactive.isActive = false

        let ended = medication("Amoxicillin", for: person, in: context)
        ended.endDate = day(2026, 7, 10)

        let deleted = medication("Warfarin", for: person, in: context)
        deleted.deletedAt = Date()

        let untimed = medication("Vitamin D", for: person, in: context, minutes: [])

        #expect(inactive.isActive == false)
        #expect(untimed.scheduleMinutes.isEmpty)
        #expect(ended.endDate != nil)
        #expect(deleted.deletedAt != nil)
        #expect(DoseReminderPlanner.requests(for: [person], on: day(2026, 7, 15), calendar: calendar).isEmpty)
    }

    @Test func deletedPersonProducesNoSpecs() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        medication("Metformin", for: person, in: context)
        person.deletedAt = Date()

        #expect(DoseReminderPlanner.requests(for: [person], on: day(2026, 7, 15), calendar: calendar).isEmpty)
    }

    // MARK: The 64-request budget

    @Test func specsAreCappedBelowTheDeviceLimit() {
        let context = makeContext()
        var people: [Person] = []

        // 5 people x 5 medications x 3 times a day = 75 wanted, past the budget.
        for index in 0..<5 {
            let person = Person(name: "Person \(index)", relationship: "P\(index)")
            context.insert(person)
            for medIndex in 0..<5 {
                medication(
                    "Med \(index)-\(medIndex)",
                    for: person,
                    in: context,
                    minutes: [8 * 60 + medIndex, 13 * 60 + medIndex, 20 * 60 + medIndex]
                )
            }
            people.append(person)
        }

        let specs = DoseReminderPlanner.requests(for: people, on: day(2026, 7, 15), calendar: calendar)

        #expect(specs.count == DoseReminderPlanner.limit)
        #expect(specs.count < DoseReminderPlanner.deviceLimit)
        // Nothing is scheduled twice under the same identifier.
        #expect(Set(specs.map(\.identifier)).count == specs.count)
    }

    @Test func capIsStableAcrossTwoCallsWithIdenticalInput() {
        let context = makeContext()
        var people: [Person] = []

        for index in 0..<5 {
            let person = Person(name: "Person \(index)", relationship: "P\(index)")
            context.insert(person)
            for medIndex in 0..<5 {
                medication(
                    "Med \(index)-\(medIndex)",
                    for: person,
                    in: context,
                    minutes: [8 * 60 + medIndex, 13 * 60 + medIndex, 20 * 60 + medIndex]
                )
            }
            people.append(person)
        }

        let now = day(2026, 7, 15)
        let first = DoseReminderPlanner.requests(for: people, on: now, calendar: calendar).map(\.identifier)
        let second = DoseReminderPlanner.requests(for: people, on: now, calendar: calendar).map(\.identifier)

        #expect(first == second)
    }

    @Test func capKeepsTheSoonestReminders() {
        let context = makeContext()
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)

        // One a minute from 00:01, so far more than the budget and in a known
        // order relative to a midnight "now".
        medication("Metformin", for: person, in: context, minutes: Array(1...90))

        let specs = DoseReminderPlanner.requests(for: [person], on: day(2026, 7, 15), calendar: calendar)
        let scheduleMinutes = specs.map { $0.hour * 60 + $0.minute }

        #expect(specs.count == DoseReminderPlanner.limit)
        // The kept ones are the soonest, in fire order, and the rest are dropped
        // rather than left to iOS to discard however it likes.
        #expect(scheduleMinutes == Array(1...DoseReminderPlanner.limit))
    }

    // MARK: Identity and copy

    @Test func identifierEncodesMedicationTimeAndWeekday() {
        let context = makeContext()
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)
        let med = medication("Metformin", for: person, in: context, minutes: [8 * 60 + 30], weekdays: [2])

        let specs = DoseReminderPlanner.requests(for: [person], on: day(2026, 7, 15), calendar: calendar)

        #expect(specs.count == 1)
        #expect(specs[0].identifier == "dose-\(med.id.uuidString)-510-2")
        #expect(specs[0].identifier.hasPrefix(ReminderSpec.identifierPrefix))
    }

    @Test func bodyNamesThePersonAndUsesNoEmDash() {
        let context = makeContext()
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)
        medication("Metformin", for: person, in: context)

        let specs = DoseReminderPlanner.requests(for: [person], on: day(2026, 7, 15), calendar: calendar)

        // The entered name, not the relationship. A notification that says
        // "Mom:" on a phone tracking two parents names neither of them.
        #expect(specs[0].body == "Eleanor: Metformin 500 mg")
        #expect(!specs[0].body.contains("\u{2014}"))
    }

    // MARK: Per-device preference

    @Test func preferenceIsOffUntilTurnedOnAndIsPerPerson() {
        let defaults = UserDefaults(suiteName: "dose-reminder-tests-\(UUID().uuidString)")!
        let mom = UUID()
        let dad = UUID()

        #expect(DoseReminderPreferences.isEnabled(personID: mom, defaults: defaults) == false)

        DoseReminderPreferences.setEnabled(true, personID: mom, defaults: defaults)
        #expect(DoseReminderPreferences.isEnabled(personID: mom, defaults: defaults))
        #expect(DoseReminderPreferences.isEnabled(personID: dad, defaults: defaults) == false)

        DoseReminderPreferences.clear(personID: mom, defaults: defaults)
        #expect(DoseReminderPreferences.isEnabled(personID: mom, defaults: defaults) == false)
    }
}
