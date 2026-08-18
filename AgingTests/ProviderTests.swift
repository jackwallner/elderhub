import Foundation
import SwiftData
import Testing

@testable import Aging

@MainActor
struct ProviderTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    // MARK: Resolution

    @Test func medicationWithProviderIDResolvesTheProvidersNameAndPhone() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let provider = Provider(name: "Dr. Patel", specialty: "Cardiology", phone: "555-0101", person: person)
        context.insert(provider)

        let med = Medication(name: "Lisinopril", person: person)
        med.prescriber = "Some Old Doctor" // must not win once an id is set
        med.providerID = provider.id
        context.insert(med)

        #expect(med.resolvedPrescriberName == "Dr. Patel")
        #expect(med.resolvedPrescriberPhone == "555-0101")
    }

    @Test func medicationWithNoProviderIDFallsBackToTheLegacyString() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let med = Medication(name: "Lisinopril", person: person)
        med.prescriber = "Dr. Patel (typed years ago)"
        context.insert(med)

        #expect(med.resolvedPrescriberName == "Dr. Patel (typed years ago)")
        #expect(med.resolvedPrescriberPhone.isEmpty)
    }

    @Test func medicationResolvesAPharmacySeparatelyFromItsPrescriber() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let prescriber = Provider(name: "Dr. Patel", person: person)
        let pharmacy = Provider(name: "CVS Main St", phone: "555-0202", isPharmacy: true, person: person)
        context.insert(prescriber)
        context.insert(pharmacy)

        let med = Medication(name: "Lisinopril", person: person)
        med.providerID = prescriber.id
        med.pharmacyID = pharmacy.id
        context.insert(med)

        #expect(med.resolvedPrescriberName == "Dr. Patel")
        #expect(med.resolvedPharmacyName == "CVS Main St")
        #expect(med.resolvedPharmacyPhone == "555-0202")
    }

    @Test func visitWithProviderIDResolvesTheProvidersName() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let provider = Provider(name: "Dr. Patel", person: person)
        context.insert(provider)

        let visit = Visit(date: Date(), provider: "Old typed name", person: person)
        visit.providerID = provider.id
        context.insert(visit)

        #expect(visit.resolvedProviderName == "Dr. Patel")
    }

    @Test func visitWithNoProviderIDFallsBackToTheLegacyString() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let visit = Visit(date: Date(), provider: "Dr. Patel (typed years ago)", person: person)
        context.insert(visit)

        #expect(visit.resolvedProviderName == "Dr. Patel (typed years ago)")
    }

    // MARK: Deletion

    @Test func deletingAProviderNullsTheMedicationReferenceButKeepsTheMedication() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let provider = Provider(name: "Dr. Patel", person: person)
        context.insert(provider)

        let med = Medication(name: "Lisinopril", person: person)
        med.providerID = provider.id
        context.insert(med)

        provider.detachAndTombstone(in: context)

        #expect(med.providerID == nil)
        #expect(med.name == "Lisinopril")

        let remainingMedications = (try? context.fetch(FetchDescriptor<Medication>())) ?? []
        #expect(remainingMedications.count == 1)
        // Tombstoned, not removed: the row has to outlive the tap for the
        // outbox to push the delete to the rest of the family.
        #expect(provider.deletedAt != nil)
        #expect(person.liveProviders.isEmpty)
    }

    @Test func deletingAPharmacyNullsThePharmacyIDButNotAnUnrelatedPrescriber() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let prescriber = Provider(name: "Dr. Patel", person: person)
        let pharmacy = Provider(name: "CVS Main St", isPharmacy: true, person: person)
        context.insert(prescriber)
        context.insert(pharmacy)

        let med = Medication(name: "Lisinopril", person: person)
        med.providerID = prescriber.id
        med.pharmacyID = pharmacy.id
        context.insert(med)

        pharmacy.detachAndTombstone(in: context)

        #expect(med.pharmacyID == nil)
        #expect(med.providerID == prescriber.id)
    }

    @Test func deletingAProviderNullsAVisitReferenceButKeepsTheVisit() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let provider = Provider(name: "Dr. Patel", person: person)
        context.insert(provider)

        let visit = Visit(date: Date(), person: person)
        visit.providerID = provider.id
        context.insert(visit)

        provider.detachAndTombstone(in: context)

        #expect(visit.providerID == nil)
        let remainingVisits = (try? context.fetch(FetchDescriptor<Visit>())) ?? []
        #expect(remainingVisits.count == 1)
    }
}
