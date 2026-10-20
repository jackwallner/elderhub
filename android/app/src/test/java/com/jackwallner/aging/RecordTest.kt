package com.jackwallner.aging

import com.jackwallner.aging.data.CareCodec
import com.jackwallner.aging.data.CareStore
import com.jackwallner.aging.data.MemoryPersistence
import com.jackwallner.aging.data.PaidBoundary
import com.jackwallner.aging.model.CareFeature
import com.jackwallner.aging.model.CareOverview
import com.jackwallner.aging.model.CareState
import com.jackwallner.aging.model.DoseLog
import com.jackwallner.aging.model.DoseStatus
import com.jackwallner.aging.model.EmergencyContact
import com.jackwallner.aging.model.MedListExporter
import com.jackwallner.aging.model.Medication
import com.jackwallner.aging.model.Person
import com.jackwallner.aging.model.Phone
import com.jackwallner.aging.model.Provider
import com.jackwallner.aging.model.SampleData
import com.jackwallner.aging.model.ScheduleEngine
import com.jackwallner.aging.model.Visit
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Parity with `AgingTests/MedListExporterTests.swift`. */
class MedListExporterTest {
    private val person = Person(name = "Eleanor Wallner", allergies = listOf("Penicillin"), conditions = listOf("Hypertension"))

    private fun text(state: CareState, p: Person = person) = MedListExporter.plainText(state, p.id, locale = Locale.US)

    @Test fun summaryIncludesAllergiesConditionsAndMedications() {
        val med = Medication(personId = person.id, name = "Lisinopril", strength = "10 mg", purpose = "blood pressure", prescriber = "Dr. Patel", scheduleMinutes = listOf(480))
        val out = text(CareState(people = listOf(person), medications = listOf(med)))
        listOf("Eleanor Wallner", "ALLERGIES: Penicillin", "CONDITIONS: Hypertension", "Lisinopril 10 mg", "for blood pressure", "Dr. Patel")
            .forEach { assertTrue(it, out.contains(it)) }
    }

    @Test fun scheduledAndAsNeededAreSeparated() {
        val scheduled = Medication(personId = person.id, name = "Metformin", strength = "500 mg", scheduleMinutes = listOf(480))
        val asNeeded = Medication(personId = person.id, name = "Acetaminophen", strength = "500 mg", isAsNeeded = true)
        val out = text(CareState(people = listOf(person), medications = listOf(scheduled, asNeeded)))
        val s = out.indexOf("SCHEDULED MEDICATIONS")
        val a = out.indexOf("AS NEEDED")
        assertTrue(s >= 0 && a >= 0)
        assertTrue(out.indexOf("Metformin") in (s + 1) until a)
        assertTrue(out.indexOf("Acetaminophen") > a)
    }

    @Test fun emptyListStillProducesAUsableCard() {
        val robert = Person(name = "Robert")
        val out = text(CareState(people = listOf(robert)), robert)
        assertTrue(out.contains("Robert"))
        assertTrue(out.contains("No active medications recorded."))
    }

    @Test fun inactiveMedicationsAreExcluded() {
        val stopped = Medication(personId = person.id, name = "Warfarin", strength = "5 mg", isActive = false)
        assertFalse(text(CareState(people = listOf(person), medications = listOf(stopped))).contains("Warfarin"))
    }

    @Test fun linkedProviderAndPharmacyPrintWithTheirPhoneNumbers() {
        val prescriber = Provider(personId = person.id, name = "Dr. Patel", phone = "555-0101")
        val pharmacy = Provider(personId = person.id, name = "CVS Main St", phone = "555-0202", isPharmacy = true)
        val med = Medication(
            personId = person.id, name = "Lisinopril", strength = "10 mg", scheduleMinutes = listOf(480),
            prescriber = "Old typed name", providerId = prescriber.id, pharmacyId = pharmacy.id,
        )
        val out = text(CareState(people = listOf(person), medications = listOf(med), providers = listOf(prescriber, pharmacy)))
        assertTrue(out.contains("Dr. Patel, 555-0101"))
        assertTrue(out.contains("pharmacy: CVS Main St, 555-0202"))
        assertFalse(out.contains("Old typed name"))
    }

    @Test fun unlinkedPrescriberFallsBackToTheLegacyStringWithNoPhone() {
        val med = Medication(personId = person.id, name = "Lisinopril", strength = "10 mg", prescriber = "Dr. Patel")
        assertTrue(text(CareState(people = listOf(person), medications = listOf(med))).contains("(Dr. Patel)"))
    }

    @Test fun missingSectionsSayNotRecordedRatherThanDisappearing() {
        val bare = Person(name = "Robert")
        val out = text(CareState(people = listOf(bare)), bare)
        listOf("ALLERGIES: not recorded", "CONDITIONS: not recorded", "EMERGENCY CONTACTS", "Not recorded", "Blood type: not recorded")
            .forEach { assertTrue(it, out.contains(it)) }
    }

    @Test fun providersWithAPhoneNumberAreExportedLikeTheCardShowsThem() {
        val doctor = Provider(personId = person.id, name = "Dr. Patel", specialty = "Cardiology", phone = "555-0101")
        val noPhone = Provider(personId = person.id, name = "Dr. Nguyen")
        val out = text(CareState(people = listOf(person), providers = listOf(doctor, noPhone)))
        assertTrue(out.contains("PROVIDERS"))
        assertTrue(out.contains("Dr. Patel (Cardiology), 555-0101"))
        assertFalse(out.contains("Dr. Nguyen"))
    }

    @Test fun aContactWithNoNumberSaysSoRatherThanTrailingAComma() {
        val contact = EmergencyContact(personId = person.id, name = "Sarah", relationship = "Daughter", isPrimary = true)
        assertTrue(text(CareState(people = listOf(person), contacts = listOf(contact))).contains("Sarah (Daughter), no phone number saved"))
    }

    @Test fun thePrimaryContactIsMarkedCallFirst() {
        val michael = EmergencyContact(personId = person.id, name = "Michael", relationship = "Son", phone = "555-987-6543")
        val sarah = EmergencyContact(personId = person.id, name = "Sarah", relationship = "Daughter", phone = "555-123-4567", isPrimary = true)
        val out = text(CareState(people = listOf(person), contacts = listOf(michael, sarah)))
        assertTrue(out.contains("CALL FIRST: Sarah (Daughter), 555-123-4567"))
        assertTrue(out.contains("  Michael (Son), 555-987-6543"))
        assertEquals(2, out.split("CALL FIRST").size)
        assertTrue(out.indexOf("Sarah") < out.indexOf("Michael"))
    }

    @Test fun aContactWhoIsNotPrimaryCarriesNoMarker() {
        val contact = EmergencyContact(personId = person.id, name = "Sarah", phone = "555")
        assertFalse(text(CareState(people = listOf(person), contacts = listOf(contact))).contains("CALL FIRST"))
    }

    @Test fun summaryCarriesTheNotAMedicalRecordDisclaimer() {
        assertTrue(text(CareState(people = listOf(person))).contains("not a medical record"))
    }

    @Test fun theHandoffPrintsTheDateOfBirthOrSaysItIsMissing() {
        val born = person.copy(birthDate = LocalDate.of(1939, 2, 3))
        val out = text(CareState(people = listOf(born)), born)
        assertTrue(out.contains("Date of birth: "))
        assertTrue(out.contains("1939"))
        assertTrue(text(CareState(people = listOf(person))).contains("Date of birth: not recorded"))
    }
}

/** Parity with `AgingTests/RefillTests.swift`. */
class RefillTest {
    private val person = Person(name = "Eleanor")
    private fun tracked(q: Double, perDose: Double = 1.0) =
        Medication(personId = person.id, name = "Metformin", tracksRefills = true, quantityRemaining = q, unitsPerDose = perDose)

    @Test fun loggingATakenDoseDecrementsByUnitsPerDose() = assertEquals(28.0, tracked(30.0, 2.0).decrementedForDoseTaken().quantityRemaining, 0.0)

    @Test fun decrementRunsOncePerCall() {
        val once = tracked(30.0).decrementedForDoseTaken()
        assertEquals(29.0, once.quantityRemaining, 0.0)
        assertEquals(28.0, once.decrementedForDoseTaken().quantityRemaining, 0.0)
    }

    @Test fun correctingATakenDosePutsTheUnitsBack() =
        assertEquals(30.0, tracked(30.0, 2.0).decrementedForDoseTaken().restoredForDoseUntaken().quantityRemaining, 0.0)

    @Test fun restoringNeverTurnsTrackingOnForAnUntrackedMedication() {
        val med = Medication(personId = person.id, name = "Metformin").restoredForDoseUntaken()
        assertFalse(med.tracksRefills)
        assertEquals(0.0, med.quantityRemaining, 0.0)
        assertNull(med.daysRemaining)
    }

    @Test fun aTrackedMedicationThatRunsOutStaysTracked() {
        val med = tracked(1.0).copy(scheduleMinutes = listOf(480)).decrementedForDoseTaken()
        assertEquals(0.0, med.quantityRemaining, 0.0)
        assertTrue(med.tracksRefills)
        assertTrue(med.isOutOfStock)
        assertEquals(0.0, med.daysRemaining!!, 0.0)
    }

    @Test fun undoingTheDoseThatEmptiedTheBottlePutsItBack() {
        val med = tracked(1.0).decrementedForDoseTaken().restoredForDoseUntaken()
        assertEquals(1.0, med.quantityRemaining, 0.0)
        assertFalse(med.isOutOfStock)
    }

    @Test fun decrementNeverGoesNegative() = assertEquals(0.0, tracked(1.0, 2.0).decrementedForDoseTaken().quantityRemaining, 0.0)

    @Test fun daysRemainingIsNilWhenAsNeeded() = assertNull(tracked(10.0).copy(isAsNeeded = true, scheduleMinutes = listOf(480)).daysRemaining)

    @Test fun daysRemainingDividesOnHandByDailyDoseRate() =
        assertEquals(5.0, tracked(20.0, 2.0).copy(scheduleMinutes = listOf(480, 1200)).daysRemaining!!, 0.0)

    @Test fun weekdayLimitedScheduleStretchesDaysRemaining() =
        assertEquals(56.0, tracked(8.0).copy(scheduleMinutes = listOf(480), weekdays = listOf(2)).daysRemaining!!, 0.0)

    @Test fun anEmptyTrackedMedicationIsStillRunningLow() {
        val med = tracked(0.0).copy(scheduleMinutes = listOf(480))
        val state = CareState(people = listOf(person), medications = listOf(med))
        assertEquals(listOf(med), state.runningLow(person.id))
    }
}

/** The store: writes land locally, dose rows are reused, refills move once. */
class CareStoreTest {
    private val zone = ZoneId.of("America/New_York")
    private val now = LocalDate.of(2026, 7, 15).atTime(12, 0).atZone(zone).toInstant()

    private fun store(): Pair<CareStore, MemoryPersistence> {
        val persistence = MemoryPersistence()
        return CareStore(persistence) to persistence
    }

    @Test fun onboardingCreatesTheFirstPersonAndPersists() {
        val (store, persistence) = store()
        val person = store.completeOnboarding(" Eleanor ", "Mom", isSelf = false, attested = true, now = now)
        assertEquals("Eleanor", person.name)
        assertEquals(now, person.surrogateAttestedAt)
        assertTrue(store.state.hasCompletedOnboarding)
        val reloaded = CareStore(persistence)
        assertEquals(listOf(person), reloaded.state.people)
    }

    @Test fun reRecordingASlotReusesItsRowAndMovesRefillsOnlyOnTakenChanges() {
        val (store, _) = store()
        val person = store.completeOnboarding("Eleanor", "Mom", false, true)
        val med = Medication(personId = person.id, name = "Metformin", scheduleMinutes = listOf(480), startDate = now.minus(3, ChronoUnit.DAYS), tracksRefills = true, quantityRemaining = 10.0)
        store.upsertMedication(med)
        val slot = ScheduleEngine.slots(store.state, person.id, now, zone).single()

        store.recordDose(slot, DoseStatus.TAKEN)
        store.recordDose(slot, DoseStatus.TAKEN)
        assertEquals(1, store.state.doses.size)
        assertEquals(DoseLog.deterministicId(med.id, slot.scheduledAt), store.state.doses.single().id)
        assertEquals(9.0, store.state.medications.single().quantityRemaining, 0.0)

        store.recordDose(slot, DoseStatus.SKIPPED)
        assertEquals(1, store.state.doses.size)
        assertEquals(10.0, store.state.medications.single().quantityRemaining, 0.0)

        store.recordDose(slot, DoseStatus.TAKEN)
        store.clearDose(slot)
        assertTrue(store.state.doses.isEmpty())
        assertEquals(10.0, store.state.medications.single().quantityRemaining, 0.0)
    }

    @Test fun dosesCarryTheCaregiversNameNeverALiteralYou() {
        val (store, _) = store()
        val person = store.completeOnboarding("Eleanor", "Mom", false, true)
        store.setCaregiverName("Jack")
        store.upsertMedication(Medication(personId = person.id, name = "Metformin", scheduleMinutes = listOf(480), startDate = now.minus(1, ChronoUnit.DAYS)))
        val slot = ScheduleEngine.slots(store.state, person.id, now, zone).single()
        store.recordDose(slot, DoseStatus.TAKEN)
        assertEquals("Jack", store.state.doses.single().recordedBy)
    }

    @Test fun onlyOneContactPerPersonIsCallFirst() {
        val (store, _) = store()
        val person = store.completeOnboarding("Eleanor", "Mom", false, true)
        val sarah = EmergencyContact(personId = person.id, name = "Sarah", isPrimary = true)
        val michael = EmergencyContact(personId = person.id, name = "Michael", isPrimary = true)
        store.upsertContact(sarah)
        store.upsertContact(michael)
        assertEquals(listOf("Michael"), store.state.contacts.filter { it.isPrimary }.map { it.name })
    }

    @Test fun deletingAPersonRemovesEverythingAboutThem() {
        val (store, _) = store()
        store.update { SampleData.withDad(SampleData.mom(now, zone), now) }
        val dad = store.state.people.first { it.name == "Robert Wallner" }
        val mom = store.state.people.first { it.name == "Eleanor Wallner" }
        store.deletePerson(dad.id)
        assertEquals(listOf(mom.id), store.state.people.map { it.id })
        assertTrue(store.state.medications.all { it.personId == mom.id })
        assertTrue(store.state.contacts.all { it.personId == mom.id })
        assertTrue(store.state.providers.all { it.personId == mom.id })
    }

    @Test fun deletingAProviderDetachesButKeepsTheMedication() {
        val (store, _) = store()
        store.update { SampleData.mom(now, zone) }
        val patel = store.state.providers.first { it.name == "Dr. Patel" }
        store.deleteProvider(patel.id)
        val lisinopril = store.state.medications.first { it.name == "Lisinopril" }
        assertNull(lisinopril.providerId)
        assertEquals("Dr. Patel", lisinopril.prescriber)
    }

    @Test fun codecRoundTripsTheWholeSampleRecord() {
        val sample = SampleData.withDad(SampleData.mom(now, zone), now)
        assertEquals(sample, CareCodec.decode(CareCodec.encode(sample)))
    }

    @Test fun aCorruptFileOpensAsAnEmptyRecordRatherThanCrashing() {
        val store = CareStore(MemoryPersistence("{ not json"))
        assertTrue(store.state.people.isEmpty())
    }

    @Test fun unknownEnumValuesFallBackInsteadOfDroppingTheRow() {
        val json = """{"people":[{"id":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","name":"Eleanor"}],
            "medications":[{"id":"3f2504e0-4f89-11d3-9a0c-0305e82c3302","person_id":"3f2504e0-4f89-11d3-9a0c-0305e82c3301","name":"X","form":"lozenge"}]}"""
        val state = CareCodec.decode(json)
        assertEquals(1, state.medications.size)
        assertEquals("Other", state.medications.single().form.label)
    }

    @Test fun freeTierIsOneCareRecipient() {
        assertTrue(PaidBoundary.canAddPerson(isUnlocked = false, peopleCount = 0))
        assertFalse(PaidBoundary.canAddPerson(isUnlocked = false, peopleCount = 1))
        assertTrue(PaidBoundary.canAddPerson(isUnlocked = true, peopleCount = 1))
        assertTrue(PaidBoundary.canAddPerson(isUnlocked = true, peopleCount = 5))
    }
}

/** Parity with the hub status lines in `CareOverview.swift` and the card's `telURL`. */
class CareOverviewTest {
    private val zone = ZoneId.of("America/New_York")
    private val now: Instant = LocalDate.of(2026, 7, 15).atTime(12, 0).atZone(zone).toInstant()

    @Test fun emptyFeaturesSayNoneYet() {
        val person = Person(name = "Robert")
        val state = CareState(people = listOf(person))
        CareFeature.entries.forEach {
            assertEquals("None yet", CareOverview.detail(it, state, person.id, now, zone))
            assertTrue(CareOverview.isEmpty(it, state, person.id))
        }
    }

    @Test fun populatedFeaturesCountWhatIsThere() {
        val state = SampleData.mom(now, zone)
        val mom = state.people.single().id
        assertEquals("4 medications", CareOverview.detail(CareFeature.MEDICATIONS, state, mom, now, zone))
        assertEquals("Next: Sun 19 Jul", CareOverview.detail(CareFeature.VISITS, state, mom, now, zone))
        assertEquals("3 saved", CareOverview.detail(CareFeature.PROVIDERS, state, mom, now, zone))
        assertEquals("2 allergies, 2 conditions, blood type", CareOverview.detail(CareFeature.HEALTH_DETAILS, state, mom, now, zone))
        assertEquals("1 contact", CareOverview.detail(CareFeature.CONTACTS, state, mom, now, zone))
    }

    @Test fun appointmentsDueLooksOneWeekAhead() {
        val person = Person(name = "Eleanor")
        val soon = Visit(personId = person.id, date = now.plus(3, ChronoUnit.DAYS), reason = "Soon")
        val later = Visit(personId = person.id, date = now.plus(10, ChronoUnit.DAYS), reason = "Later")
        val past = Visit(personId = person.id, date = now.minus(1, ChronoUnit.DAYS), reason = "Past")
        val state = CareState(people = listOf(person), visits = listOf(later, past, soon))
        assertEquals(listOf("Soon"), state.appointmentsDue(person.id, now).map { it.reason })
        assertEquals(listOf("Past"), state.pastVisits(person.id, now).map { it.reason })
    }

    @Test fun onlyAChosenTimeOfDayIsShown() {
        val person = Person(name = "Eleanor")
        val dateOnly = Visit(personId = person.id, date = LocalDate.of(2026, 7, 20).atStartOfDay(zone).toInstant())
        val timed = Visit(personId = person.id, date = LocalDate.of(2026, 7, 20).atTime(9, 30).atZone(zone).toInstant())
        val pastTimed = Visit(personId = person.id, date = LocalDate.of(2026, 7, 1).atTime(17, 4).atZone(zone).toInstant())
        assertFalse(dateOnly.hasTimeOfDay(zone, now))
        assertTrue(timed.hasTimeOfDay(zone, now))
        assertFalse(pastTimed.hasTimeOfDay(zone, now))
    }

    @Test fun phoneNumbersDialWithoutTheirExtension() {
        assertEquals("5552001010", Phone.dialable("(555) 200-1010"))
        assertEquals("+15552001010", Phone.dialable("+1 555 200 1010 x22"))
        assertEquals("5550101", Phone.dialable("555-0101#3"))
        assertNull(Phone.dialable("ask the front desk"))
    }

    @Test fun displayLabelPrefersTheName() {
        assertEquals("Eleanor", Person(name = " Eleanor ", relationship = "Mom").displayLabel)
        assertEquals("Mom", Person(relationship = "Mom").displayLabel)
        assertEquals("This person", Person().displayLabel)
    }
}
