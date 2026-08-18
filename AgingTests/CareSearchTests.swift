import Foundation
import SwiftData
import Testing

@testable import Aging

@MainActor
struct CareSearchTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    // MARK: Empty query

    @Test func emptyQueryReturnsNothingRatherThanEverything() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        let med = Medication(name: "Lisinopril", person: person)
        context.insert(med)

        #expect(CareSearch.search(query: "", people: [person]).isEmpty)
        #expect(CareSearch.search(query: "   ", people: [person]).isEmpty)
    }

    // MARK: Multi-token

    @Test func multiTokenQueryRequiresAllTokensToMatch() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let med = Medication(name: "Lisinopril", purpose: "blood pressure", person: person)
        context.insert(med)

        let bothTokens = CareSearch.search(query: "lisinopril pressure", people: [person])
        #expect(bothTokens.contains { $0.kind == .medication })

        let missingToken = CareSearch.search(query: "lisinopril xyz", people: [person])
        #expect(missingToken.isEmpty)
    }

    // MARK: Diacritic- and case-insensitive

    @Test func matchingIsDiacriticAndCaseInsensitive() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let provider = Provider(name: "Dr. José Peña", specialty: "Audiology", person: person)
        context.insert(provider)

        let results = CareSearch.search(query: "JOSE pena", people: [person])
        #expect(results.contains { $0.kind == .provider })
    }

    // MARK: Soft-deleted rows

    @Test func softDeletedRecordsNeverSurface() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let med = Medication(name: "Lisinopril", person: person)
        med.deletedAt = Date()
        context.insert(med)

        let event = CareEvent(kind: .fall, note: "Fell near the hearing aid charger", person: person)
        event.deletedAt = Date()
        context.insert(event)

        #expect(CareSearch.search(query: "lisinopril", people: [person]).isEmpty)
        #expect(CareSearch.search(query: "hearing", people: [person]).isEmpty)
    }

    @Test func softDeletedPersonNeverSurfaces() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        person.deletedAt = Date()
        context.insert(person)

        let med = Medication(name: "Lisinopril", person: person)
        context.insert(med)

        #expect(CareSearch.search(query: "lisinopril", people: [person]).isEmpty)
    }

    // MARK: Field priority

    @Test func fieldPriorityRanksNameMatchesAboveNoteMatches() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let namedHearing = Medication(name: "Hearing Support", person: person)
        context.insert(namedHearing)

        let notedHearing = Medication(name: "Aspirin", person: person)
        notedHearing.instructions = "Discussed at the hearing aid fitting"
        context.insert(notedHearing)

        let results = CareSearch.search(query: "hearing", people: [person])
        #expect(results.count == 2)
        #expect(results.first?.title == "Hearing Support")
        #expect(results.first?.matchedField == "name")
        #expect(results.last?.matchedField == "instructions")
    }

    @Test func withinTheSamePriorityMoreRecentSortsFirst() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let older = Medication(name: "Hearing Aid Batteries", person: person)
        older.startDate = Date(timeIntervalSince1970: 0)
        context.insert(older)

        let newer = Medication(name: "Hearing Aid Wax Guards", person: person)
        newer.startDate = Date(timeIntervalSince1970: 1_000_000)
        context.insert(newer)

        let results = CareSearch.search(query: "hearing", people: [person])
        #expect(results.map(\.title) == ["Hearing Aid Wax Guards", "Hearing Aid Batteries"])
    }

    // MARK: Cross-person scope

    @Test func personNameRidesAlongOnEveryHitAcrossPeople() {
        let context = makeContext()
        let mom = Person(name: "Eleanor")
        context.insert(mom)
        let dad = Person(name: "Robert")
        context.insert(dad)

        let momMed = Medication(name: "Hearing Aid Batteries", person: mom)
        context.insert(momMed)
        let dadVisit = Visit(reason: "Hearing test", person: dad)
        context.insert(dadVisit)

        let results = CareSearch.search(query: "hearing", people: [mom, dad])
        #expect(results.contains { $0.personName == "Eleanor" && $0.kind == .medication })
        #expect(results.contains { $0.personName == "Robert" && $0.kind == .visit })
    }

    // MARK: Cap per kind

    @Test func resultsAreCappedPerKind() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        for index in 0..<10 {
            let med = Medication(name: "Hearing Med \(index)", person: person)
            context.insert(med)
        }

        let results = CareSearch.search(query: "hearing", people: [person], limitPerKind: 3)
        #expect(results.filter { $0.kind == .medication }.count == 3)
    }

    // MARK: Field coverage

    @Test func personConditionsAllergiesAndNotesAreSearchable() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        person.conditions = ["Hearing loss"]
        person.allergies = ["Penicillin"]
        person.notes = "Prefers morning appointments"
        context.insert(person)

        #expect(CareSearch.search(query: "hearing loss", people: [person]).contains { $0.kind == .person })
        #expect(CareSearch.search(query: "penicillin", people: [person]).contains { $0.kind == .person })
        #expect(CareSearch.search(query: "morning", people: [person]).contains { $0.kind == .person })
    }

    @Test func emergencyContactNameIsSearchable() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        let contact = EmergencyContact(name: "Jack Wallner", person: person)
        context.insert(contact)

        #expect(CareSearch.search(query: "wallner", people: [person]).contains { $0.kind == .emergencyContact })
    }

    @Test func visitFieldsAreSearchable() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        let visit = Visit(provider: "Dr. Kim", reason: "Annual physical", person: person)
        visit.notes = "Discussed hearing loss"
        visit.followUp = "Refer to audiologist"
        context.insert(visit)

        #expect(CareSearch.search(query: "kim", people: [person]).contains { $0.kind == .visit })
        #expect(CareSearch.search(query: "physical", people: [person]).contains { $0.kind == .visit })
        #expect(CareSearch.search(query: "hearing", people: [person]).contains { $0.kind == .visit })
        #expect(CareSearch.search(query: "audiologist", people: [person]).contains { $0.kind == .visit })
    }

    @Test func providerFieldsAreSearchable() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)
        let provider = Provider(
            name: "Dr. Kim",
            specialty: "Audiology",
            notes: "Bring hearing aids to every visit",
            person: person
        )
        context.insert(provider)

        #expect(CareSearch.search(query: "audiology", people: [person]).contains { $0.kind == .provider })
        #expect(CareSearch.search(query: "hearing aids", people: [person]).contains { $0.kind == .provider })
    }

    /// A visit linked to a `Provider` shows that provider's name on the row and
    /// in the hit title, so that is the name the user types. Matching the
    /// legacy free-text column instead means searching for what is on screen
    /// finds nothing.
    @Test func visitIsFoundByItsLinkedProvidersName() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let provider = Provider(name: "Dr. Nakamura", specialty: "Cardiology", person: person)
        context.insert(provider)

        let visit = Visit(reason: "Annual physical", person: person)
        visit.providerID = provider.id
        context.insert(visit)

        let hits = CareSearch.search(query: "nakamura", people: [person])
        #expect(hits.contains { $0.kind == .visit })
        #expect(hits.first { $0.kind == .visit }?.title == "Visit: Dr. Nakamura")
    }

    /// Same reasoning for medications: the prescriber and pharmacy print on the
    /// medication list, so they have to be findable.
    @Test func medicationIsFoundByItsPrescriber() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let typed = Medication(name: "Lisinopril", person: person)
        typed.prescriber = "Dr. Okonkwo"
        context.insert(typed)

        let provider = Provider(name: "Dr. Nakamura", person: person)
        context.insert(provider)
        let linked = Medication(name: "Metformin", person: person)
        linked.providerID = provider.id
        context.insert(linked)

        #expect(CareSearch.search(query: "okonkwo", people: [person])
            .contains { $0.kind == .medication && $0.title.contains("Lisinopril") })
        #expect(CareSearch.search(query: "nakamura", people: [person])
            .contains { $0.kind == .medication && $0.title.contains("Metformin") })
    }
}
