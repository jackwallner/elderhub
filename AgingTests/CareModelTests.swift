import Foundation
import SwiftData
import Testing

@testable import Aging

@MainActor
struct CareModelTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    @Test func displayNameCombinesNameAndStrength() {
        let med = Medication(name: "Lisinopril", strength: "10 mg")
        #expect(med.displayName == "Lisinopril 10 mg")

        let bare = Medication(name: "Aspirin")
        #expect(bare.displayName == "Aspirin")
    }

    @Test func displayLabelPrefersTheEnteredName() {
        // The entered name is the identity, on every screen. The relationship
        // is a subtitle, not a second name for the same row.
        let withRelationship = Person(name: "Eleanor Wallner", relationship: "Mom")
        #expect(withRelationship.displayLabel == "Eleanor Wallner")

        let withoutRelationship = Person(name: "Eleanor Wallner")
        #expect(withoutRelationship.displayLabel == "Eleanor Wallner")

        // A solo record used to read "Me's care record".
        let solo = Person(name: "Jack", relationship: "Me", isSelf: true)
        #expect(solo.displayLabel == "Jack")
    }

    @Test func displayLabelFallsBackWhenThereIsNoName() {
        let relationshipOnly = Person(name: "  ", relationship: "Dad")
        #expect(relationshipOnly.displayLabel == "Dad")

        let neither = Person(name: "")
        #expect(neither.displayLabel == "This person")
    }

    @Test func activeMedicationsExcludeStoppedOnesAndSortByName() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let metformin = Medication(name: "Metformin", person: person)
        let aspirin = Medication(name: "Aspirin", person: person)
        let stopped = Medication(name: "Warfarin", person: person)
        stopped.isActive = false
        context.insert(metformin)
        context.insert(aspirin)
        context.insert(stopped)

        let active = person.activeMedications
        let names = active.map(\.name)

        #expect(active.count == 2)
        #expect(names == ["Aspirin", "Metformin"])
    }

    @Test func bloodPressureReadingRendersAsAPair() {
        let reading = VitalReading(kind: .bloodPressure, primaryValue: 148, secondaryValue: 88)
        #expect(reading.displayValue == "148/88")
        #expect(reading.kind.isPaired)
    }

    @Test func singleValueReadingDropsTrailingZero() {
        let weight = VitalReading(kind: .weight, primaryValue: 163)
        #expect(weight.displayValue == "163")

        let precise = VitalReading(kind: .weight, primaryValue: 163.4)
        #expect(precise.displayValue == "163.4")
    }

    @Test func deletingAPersonCascadesToTheirRecords() throws {
        let container = CareModelStore.makeInMemoryContainer()
        let context = ModelContext(container)

        let person = Person(name: "Eleanor")
        context.insert(person)
        context.insert(Medication(name: "Metformin", person: person))
        context.insert(Visit(provider: "Dr. Patel", person: person))
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Medication>()) == 1)

        context.delete(person)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Person>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Medication>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Visit>()) == 0)
    }

    @Test func personInitialsHandleOneAndTwoWordNames() {
        #expect(Person(name: "Eleanor Wallner").initials == "EW")
        #expect(Person(name: "Eleanor").initials == "E")
        #expect(Person(name: "").initials == "?")
    }
}
