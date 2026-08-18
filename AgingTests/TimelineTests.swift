import Foundation
import SwiftData
import Testing

@testable import Aging

@MainActor
struct TimelineTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    // MARK: Empty

    @Test func emptyPersonYieldsEmptyArray() {
        let entries = TimelineBuilder.build(personID: UUID())
        #expect(entries.isEmpty)
    }

    // MARK: Sorting

    @Test func entriesSortStrictlyDescendingAcrossMixedTypes() {
        let context = makeContext()
        let person = Person(name: "Eleanor", relationship: "Mom")
        context.insert(person)

        let visit = Visit(date: day(2026, 3, 10), reason: "Checkup", person: person)
        context.insert(visit)

        let vital = VitalReading(kind: .weight, primaryValue: 150, recordedAt: day(2026, 5, 1), person: person)
        context.insert(vital)

        let event = CareEvent(kind: .fall, occurredAt: day(2026, 1, 20), person: person)
        context.insert(event)

        let checkIn = CheckInRecord(
            groupID: nil,
            personID: person.id,
            source: .selfPressed,
            pressedAt: day(2026, 6, 1)
        )
        context.insert(checkIn)

        let entries = TimelineBuilder.build(
            personID: person.id,
            visits: [visit],
            vitals: [vital],
            careEvents: [event],
            checkIns: [checkIn]
        )

        let dates = entries.map(\.date)
        #expect(dates == dates.sorted(by: >))
        #expect(entries.count == 4)
        #expect(entries.first?.kind == .checkIn)
        #expect(entries.last?.kind == .careEvent)
    }

    // MARK: Dose filtering

    @Test func takenDosesAreExcludedAndMissedDosesAreIncluded() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let med = Medication(name: "Metformin", person: person)
        context.insert(med)

        let taken = DoseLog(scheduledAt: day(2026, 4, 1), status: .taken, medication: med)
        let missed = DoseLog(scheduledAt: day(2026, 4, 2), status: .missed, medication: med)
        let skipped = DoseLog(scheduledAt: day(2026, 4, 3), status: .skipped, medication: med)
        context.insert(taken)
        context.insert(missed)
        context.insert(skipped)

        let entries = TimelineBuilder.build(
            personID: person.id,
            medications: [],
            doseLogs: [taken, missed, skipped]
        )

        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.kind == .doseIssue })
        #expect(Set(entries.map(\.date)) == [missed.scheduledAt, skipped.scheduledAt])
    }

    // MARK: Medication started / stopped

    @Test func medicationWithEndDateProducesStartedAndStoppedEntries() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let med = Medication(name: "Lisinopril", strength: "10 mg", person: person)
        med.startDate = day(2026, 1, 1)
        med.endDate = day(2026, 2, 1)
        context.insert(med)

        let entries = TimelineBuilder.build(personID: person.id, medications: [med])

        #expect(entries.count == 2)
        #expect(entries.contains { $0.kind == .medicationStarted && $0.date == med.startDate })
        #expect(entries.contains { $0.kind == .medicationStopped && $0.date == med.endDate })
    }

    @Test func medicationWithoutEndDateProducesOnlyAStartedEntry() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let med = Medication(name: "Atorvastatin", person: person)
        med.startDate = day(2026, 1, 1)
        context.insert(med)

        let entries = TimelineBuilder.build(personID: person.id, medications: [med])

        #expect(entries.count == 1)
        #expect(entries[0].kind == .medicationStarted)
    }

    // MARK: Deleted rows

    @Test func softDeletedRowsAreExcluded() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let visit = Visit(date: day(2026, 3, 10), reason: "Checkup", person: person)
        visit.deletedAt = Date()
        context.insert(visit)

        let entries = TimelineBuilder.build(personID: person.id, visits: [visit])
        #expect(entries.isEmpty)
    }
}
