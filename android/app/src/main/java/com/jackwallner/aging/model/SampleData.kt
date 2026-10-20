package com.jackwallner.aging.model

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** Port of `Aging/Support/SampleData.swift`, for debug launches, screenshots and tests. */
object SampleData {

    fun mom(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): CareState {
        val mom = Person(
            name = "Eleanor Wallner", relationship = "Mom", birthDate = LocalDate.of(1947, 4, 12), bloodType = "O+",
            allergies = listOf("Penicillin", "Sulfa drugs"), conditions = listOf("Hypertension", "Type 2 diabetes"),
        )
        val primaryCare = Provider(personId = mom.id, name = "Dr. Patel", specialty = "Primary care", phone = "(555) 200-1010")
        val audiologist = Provider(
            personId = mom.id, name = "Dr. Chen", specialty = "Audiology", phone = "(555) 200-3030",
            notes = "Fits and adjusts hearing aids.",
        )
        val pharmacy = Provider(personId = mom.id, name = "CVS Pharmacy - Main St", phone = "(555) 200-5050", isPharmacy = true)
        val start = now.minus(30, ChronoUnit.DAYS)
        val meds = listOf(
            Medication(
                personId = mom.id, name = "Lisinopril", strength = "10 mg", purpose = "blood pressure",
                scheduleMinutes = listOf(8 * 60), prescriber = "Dr. Patel", instructions = "Take with food",
                providerId = primaryCare.id, pharmacyId = pharmacy.id, startDate = start,
            ),
            Medication(
                personId = mom.id, name = "Metformin", strength = "500 mg", purpose = "blood sugar",
                scheduleMinutes = listOf(8 * 60, 19 * 60), prescriber = "Dr. Patel",
                providerId = primaryCare.id, pharmacyId = pharmacy.id, startDate = start,
                tracksRefills = true, quantityRemaining = 9.0,
            ),
            Medication(personId = mom.id, name = "Acetaminophen", strength = "500 mg", purpose = "joint pain", isAsNeeded = true, startDate = start),
            Medication(
                personId = mom.id, name = "Hearing Aid Batteries", strength = "size 312", form = MedicationForm.OTHER,
                purpose = "hearing aid", isAsNeeded = true, instructions = "Replace weekly. Keep spares in the visit bag.",
                pharmacyId = pharmacy.id, startDate = start,
            ),
        )
        val contact = EmergencyContact(personId = mom.id, name = "Jack Wallner", relationship = "Son", phone = "(555) 010-4477", isPrimary = true)
        val today = now.atZone(zone).toLocalDate()
        val visits = listOf(
            Visit(
                personId = mom.id, date = now.minus(12, ChronoUnit.DAYS), provider = "Dr. Patel", specialty = "Primary care",
                reason = "Three month check",
                notes = "BP still running high in the mornings. Keep logging readings before breakfast and bring the numbers to the next visit.",
                followUp = "Recheck in 3 months",
            ),
            Visit(
                personId = mom.id, date = now.minus(40, ChronoUnit.DAYS), provider = "Dr. Chen", specialty = "Audiology",
                reason = "Annual hearing screening",
                notes = "Mild high-frequency hearing loss, worse in the left ear. Discussed hearing aid options.",
                followUp = "Fit hearing aids in two weeks",
            ),
            Visit(
                personId = mom.id, date = today.plusDays(4).atTime(10, 15).atZone(zone).toInstant(), provider = "Dr. Patel",
                specialty = "Primary care", reason = "Blood pressure review", notes = "Ask whether the morning dose can move later.",
            ),
        )
        // This morning's Lisinopril is already marked, so Today shows a recorded row beside pending ones.
        val morning = meds[0].doseTimes(now, zone).firstOrNull()
        val doses = listOfNotNull(
            morning?.takeIf { it < now }?.let { DoseLog.create(meds[0].id, it, DoseStatus.TAKEN, "Jack", it.plusSeconds(240)) },
        )
        return CareState(
            people = listOf(mom), medications = meds, doses = doses, visits = visits, contacts = listOf(contact),
            providers = listOf(primaryCare, audiologist, pharmacy), caregiverName = "Jack", hasCompletedOnboarding = true,
        )
    }

    /** Adds Dad: the second care recipient, which only Plus allows. */
    fun withDad(state: CareState, now: Instant = Instant.now()): CareState {
        val dad = Person(name = "Robert Wallner", relationship = "Dad", birthDate = LocalDate.of(1944, 9, 3))
        val cardiologist = Provider(personId = dad.id, name = "Dr. Osei", specialty = "Cardiology", phone = "(555) 200-7070")
        val atorvastatin = Medication(
            personId = dad.id, name = "Atorvastatin", strength = "20 mg", purpose = "cholesterol",
            scheduleMinutes = listOf(21 * 60), prescriber = "Dr. Osei", providerId = cardiologist.id,
            startDate = now.minus(30, ChronoUnit.DAYS),
        )
        val contact = EmergencyContact(personId = dad.id, name = "Jack Wallner", relationship = "Son", phone = "(555) 010-4477", isPrimary = true)
        return state.copy(
            people = state.people + dad,
            medications = state.medications + atorvastatin,
            contacts = state.contacts + contact,
            providers = state.providers + cardiologist,
        )
    }
}
