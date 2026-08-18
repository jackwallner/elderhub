import Foundation
import SwiftData
import Testing

@testable import Aging

@MainActor
struct ScheduleEngineTests {

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

    @Test func scheduledMedicationProducesOneSlotPerTime() {
        let context = makeContext()
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)

        let med = Medication(name: "Metformin", strength: "500 mg", person: person)
        med.scheduleMinutes = [8 * 60, 19 * 60]
        med.startDate = day(2026, 7, 1)
        context.insert(med)

        let slots = ScheduleEngine.slots(for: person, on: day(2026, 7, 15), calendar: calendar)

        // `allSatisfy` is rethrows; calling it inside #expect trips the macro's
        // throwing-call analysis, so resolve it first.
        let allPending = slots.allSatisfy(\.isPending)

        #expect(slots.count == 2)
        #expect(allPending)
        #expect(slots[0].scheduledAt < slots[1].scheduledAt)
    }

    @Test func asNeededMedicationIsNeverScheduled() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let med = Medication(name: "Acetaminophen", person: person)
        med.isAsNeeded = true
        med.scheduleMinutes = [8 * 60]
        context.insert(med)

        #expect(ScheduleEngine.slots(for: person, on: day(2026, 7, 15), calendar: calendar).isEmpty)
    }

    @Test func medicationIsNotScheduledBeforeItStarts() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let med = Medication(name: "Lisinopril", person: person)
        med.scheduleMinutes = [8 * 60]
        med.startDate = day(2026, 7, 20)
        context.insert(med)

        #expect(ScheduleEngine.slots(for: person, on: day(2026, 7, 15), calendar: calendar).isEmpty)
        #expect(ScheduleEngine.slots(for: person, on: day(2026, 7, 21), calendar: calendar).count == 1)
    }

    @Test func weekdayRestrictionIsHonored() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let med = Medication(name: "Alendronate", person: person)
        med.scheduleMinutes = [7 * 60]
        med.startDate = day(2026, 7, 1)
        // 2 == Monday in Calendar's 1-indexed, Sunday-first numbering.
        med.weekdays = [2]
        context.insert(med)

        // 2026-07-13 is a Monday, 2026-07-14 is a Tuesday.
        #expect(ScheduleEngine.slots(for: person, on: day(2026, 7, 13), calendar: calendar).count == 1)
        #expect(ScheduleEngine.slots(for: person, on: day(2026, 7, 14), calendar: calendar).isEmpty)
    }

    @Test func loggedDoseIsMatchedToItsSlot() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let med = Medication(name: "Metformin", person: person)
        med.scheduleMinutes = [8 * 60]
        med.startDate = day(2026, 7, 1)
        context.insert(med)

        let target = day(2026, 7, 15)
        let doseTime = med.doseTimes(on: target, calendar: calendar)[0]
        let log = DoseLog(scheduledAt: doseTime, status: .taken, recordedBy: "You", medication: med)
        context.insert(log)

        let slots = ScheduleEngine.slots(for: person, on: target, calendar: calendar)
        #expect(slots.count == 1)
        #expect(slots[0].status == .taken)
        #expect(slots[0].recordedBy == "You")
        #expect(!slots[0].isPending)
    }

    @Test func adherenceCountsTakenOverScheduled() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let med = Medication(name: "Metformin", person: person)
        med.scheduleMinutes = [8 * 60]
        med.startDate = day(2026, 7, 1)
        context.insert(med)

        let end = day(2026, 7, 15)
        // Take 2 of the 4 doses in the window.
        for offset in 0..<2 {
            let target = calendar.date(byAdding: .day, value: -offset, to: end)!
            let doseTime = med.doseTimes(on: target, calendar: calendar)[0]
            context.insert(DoseLog(scheduledAt: doseTime, status: .taken, medication: med))
        }

        let adherence = ScheduleEngine.adherence(for: person, days: 4, endingOn: end, calendar: calendar)
        #expect(adherence == 0.5)
    }

    @Test func adherenceIsNilWithNothingScheduled() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        #expect(ScheduleEngine.adherence(for: person, days: 7, endingOn: day(2026, 7, 15), calendar: calendar) == nil)
    }

    @Test func minutesRoundTripThroughTimeLabel() {
        let noon = calendar.date(bySettingHour: 12, minute: 30, second: 0, of: Date())!
        #expect(ScheduleEngine.minutes(from: noon, calendar: calendar) == 12 * 60 + 30)
    }
}
