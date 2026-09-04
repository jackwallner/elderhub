import Foundation
import SwiftData
import Testing

@testable import Aging

@MainActor
struct MedListExporterTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    @Test func summaryIncludesAllergiesConditionsAndMedications() {
        let context = makeContext()
        let person = Person(name: "Eleanor Wallner", relationship: "Mom")
        person.allergies = ["Penicillin"]
        person.conditions = ["Hypertension"]
        context.insert(person)

        let med = Medication(
            name: "Lisinopril",
            strength: "10 mg",
            purpose: "blood pressure",
            person: person
        )
        med.scheduleMinutes = [8 * 60]
        med.prescriber = "Dr. Patel"
        context.insert(med)

        let output = MedListExporter.plainText(for: person)

        #expect(output.contains("Eleanor Wallner"))
        #expect(output.contains("ALLERGIES: Penicillin"))
        #expect(output.contains("CONDITIONS: Hypertension"))
        #expect(output.contains("Lisinopril 10 mg"))
        #expect(output.contains("for blood pressure"))
        #expect(output.contains("Dr. Patel"))
    }

    @Test func scheduledAndAsNeededAreSeparated() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let scheduled = Medication(name: "Metformin", strength: "500 mg", person: person)
        scheduled.scheduleMinutes = [8 * 60]
        context.insert(scheduled)

        let asNeeded = Medication(name: "Acetaminophen", strength: "500 mg", person: person)
        asNeeded.isAsNeeded = true
        context.insert(asNeeded)

        let output = MedListExporter.plainText(for: person)

        #expect(output.contains("SCHEDULED MEDICATIONS"))
        #expect(output.contains("AS NEEDED"))

        let scheduledRange = output.range(of: "SCHEDULED MEDICATIONS")!
        let asNeededRange = output.range(of: "AS NEEDED")!
        let metforminRange = output.range(of: "Metformin")!
        let acetaminophenRange = output.range(of: "Acetaminophen")!

        #expect(metforminRange.lowerBound > scheduledRange.lowerBound)
        #expect(metforminRange.lowerBound < asNeededRange.lowerBound)
        #expect(acetaminophenRange.lowerBound > asNeededRange.lowerBound)
    }

    @Test func emptyListStillProducesAUsableCard() {
        let context = makeContext()
        let person = Person(name: "Robert")
        context.insert(person)

        let output = MedListExporter.plainText(for: person)

        #expect(output.contains("Robert"))
        #expect(output.contains("No active medications recorded."))
    }

    @Test func inactiveMedicationsAreExcluded() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let stopped = Medication(name: "Warfarin", strength: "5 mg", person: person)
        stopped.isActive = false
        context.insert(stopped)

        let output = MedListExporter.plainText(for: person)
        #expect(!output.contains("Warfarin"))
    }

    @Test func linkedProviderAndPharmacyPrintWithTheirPhoneNumbers() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let prescriber = Provider(name: "Dr. Patel", phone: "555-0101", person: person)
        let pharmacy = Provider(name: "CVS Main St", phone: "555-0202", isPharmacy: true, person: person)
        context.insert(prescriber)
        context.insert(pharmacy)

        let med = Medication(name: "Lisinopril", strength: "10 mg", person: person)
        med.scheduleMinutes = [8 * 60]
        med.prescriber = "Old typed name" // must not win once an id is set
        med.providerID = prescriber.id
        med.pharmacyID = pharmacy.id
        context.insert(med)

        let output = MedListExporter.plainText(for: person)

        #expect(output.contains("Dr. Patel, 555-0101"))
        #expect(output.contains("pharmacy: CVS Main St, 555-0202"))
        #expect(!output.contains("Old typed name"))
    }

    @Test func unlinkedPrescriberFallsBackToTheLegacyStringWithNoPhone() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let med = Medication(name: "Lisinopril", strength: "10 mg", person: person)
        med.prescriber = "Dr. Patel"
        context.insert(med)

        let output = MedListExporter.plainText(for: person)

        #expect(output.contains("(Dr. Patel)"))
    }

    /// The sheet is read by someone who was not there when it was filled in,
    /// so a missing section has to be distinguishable from a negative answer.
    /// Leaving ALLERGIES off entirely lets the reader assume there are none.
    @Test func missingSectionsSayNotRecordedRatherThanDisappearing() {
        let context = makeContext()
        let person = Person(name: "Robert")
        context.insert(person)

        let output = MedListExporter.plainText(for: person)

        #expect(output.contains("ALLERGIES: not recorded"))
        #expect(output.contains("CONDITIONS: not recorded"))
        #expect(output.contains("EMERGENCY CONTACTS"))
        #expect(output.contains("Not recorded"))
    }

    /// The card shows every provider with a phone number, and the shared sheet
    /// has to carry the same ones or the recipient is missing a number the
    /// sender believes they sent.
    @Test func providersWithAPhoneNumberAreExportedLikeTheCardShowsThem() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let doctor = Provider(name: "Dr. Patel", phone: "555-0101", person: person)
        doctor.specialty = "Cardiology"
        let unreachable = Provider(name: "Dr. Nguyen", person: person)
        context.insert(doctor)
        context.insert(unreachable)

        let output = MedListExporter.plainText(for: person)

        #expect(output.contains("PROVIDERS"))
        #expect(output.contains("Dr. Patel (Cardiology), 555-0101"))
        // No number, nothing to call: off the card, so off the sheet too.
        #expect(!output.contains("Dr. Nguyen"))
    }

    @Test func aContactWithNoNumberSaysSoRatherThanTrailingAComma() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let contact = EmergencyContact(name: "Sarah", person: person)
        contact.relationship = "Daughter"
        contact.isPrimary = true
        context.insert(contact)

        let output = MedListExporter.plainText(for: person)

        #expect(output.contains("Sarah (Daughter), no phone number saved"))
    }

    /// The whole point of marking a contact primary. Order alone says nothing
    /// to somebody reading this off a printout who has never seen the app.
    @Test func thePrimaryContactIsMarkedCallFirst() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let primary = EmergencyContact(name: "Sarah", person: person)
        primary.relationship = "Daughter"
        primary.phone = "555-123-4567"
        primary.isPrimary = true
        context.insert(primary)

        let other = EmergencyContact(name: "Michael", person: person)
        other.relationship = "Son"
        other.phone = "555-987-6543"
        context.insert(other)

        let output = MedListExporter.plainText(for: person)

        #expect(output.contains("CALL FIRST: Sarah (Daughter), 555-123-4567"))
        // Exactly one, and not on the contact who is not primary.
        #expect(output.contains("  Michael (Son), 555-987-6543"))
        #expect(output.components(separatedBy: "CALL FIRST").count == 2)
    }

    @Test func aContactWhoIsNotPrimaryCarriesNoMarker() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        let contact = EmergencyContact(name: "Sarah", person: person)
        contact.phone = "555-123-4567"
        context.insert(contact)

        #expect(!MedListExporter.plainText(for: person).contains("CALL FIRST"))
    }

    @Test func summaryCarriesTheNotAMedicalRecordDisclaimer() {
        let context = makeContext()
        let person = Person(name: "Eleanor")
        context.insert(person)

        #expect(MedListExporter.plainText(for: person).contains("not a medical record"))
    }
    /// Onboarding promises a date of birth prints on the handoff, and it did
    /// not: only an age, which is not what a hospital asks for and is not a
    /// value a clinician can match a page to a patient with. Named when
    /// missing, like the blood-type line above it.
    @Test func theHandoffPrintsTheDateOfBirthOrSaysItIsMissing() {
        let context = makeContext()
        let born = Calendar.current.date(from: DateComponents(year: 1939, month: 7, day: 13))!
        let person = Person(name: "Eleanor Wallner", relationship: "Mom", birthDate: born)
        context.insert(person)

        let text = MedListExporter.plainText(for: person)
        #expect(text.contains("Date of birth: "))
        #expect(text.contains("1939"))

        let unknown = Person(name: "Frank Wallner", relationship: "Dad")
        context.insert(unknown)
        #expect(MedListExporter.plainText(for: unknown).contains("Date of birth: not recorded"))
    }

}
