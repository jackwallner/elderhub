// Repro suite for state-machines-2026-11-24.md. Not in the test target:
// copy it into AgingTests/ to run it
// (`gh-sim test --scheme Aging --only AgingTests/StateMachineAuditRepro`).
import Foundation
import SwiftData
import Testing

@testable import Aging

@MainActor
struct StateMachineAuditRepro {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// One tablet a day, warn at 7 days left, 7 on hand: the supply reaches
    /// its threshold today.
    private func medicationAtItsThreshold(in context: ModelContext) -> Person {
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)
        let med = Medication(name: "Metformin", strength: "500 mg", person: person)
        med.scheduleMinutes = [20 * 60]
        med.tracksRefills = true
        med.quantityRemaining = 7
        med.unitsPerDose = 1
        med.refillThresholdDays = 7
        context.insert(med)
        return person
    }

    private func fireDate(_ spec: RefillReminderSpec) -> Date? {
        calendar.date(from: spec.dateComponents)
    }

    /// M1. The 8pm dose that brings the supply to its threshold is logged,
    /// and the next refresh (a foreground, or saving the medication) runs at
    /// 8:05pm. The refill reminder iOS is handed is for 9:00 this morning,
    /// a non-repeating trigger that has already passed and never fires.
    @Test func m1RefillReminderPlannedAfterNineIsStillInTheFuture() {
        let context = ModelContext(CareModelStore.makeInMemoryContainer())
        let person = medicationAtItsThreshold(in: context)
        let now = at(2026, 11, 24, 20, 5)

        // Preconditions: the medication is tracked and exactly at its threshold.
        let med = person.liveMedications[0]
        #expect(med.daysRemaining == 7)
        #expect(med.refillThresholdDays == 7)

        let specs = RefillReminderPlanner.requests(for: [person], on: now, calendar: calendar)
        #expect(specs.count == 1)
        let fire = specs.first.flatMap(fireDate)
        #expect(fire.map { $0 > now } == true, "refill reminder handed to iOS for \(String(describing: fire)), before now \(now)")
    }

    /// Control: the same supply planned at 7am gets today's 9:00, which is
    /// still ahead.
    @Test func m1ControlRefillReminderPlannedBeforeNineFiresAtNine() {
        let context = ModelContext(CareModelStore.makeInMemoryContainer())
        let person = medicationAtItsThreshold(in: context)
        let now = at(2026, 11, 24, 7, 0)

        let specs = RefillReminderPlanner.requests(for: [person], on: now, calendar: calendar)
        #expect(specs.count == 1)
        #expect(specs.first.flatMap(fireDate) == at(2026, 11, 24, 9, 0))
    }
}
