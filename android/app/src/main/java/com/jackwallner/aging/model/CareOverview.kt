package com.jackwallner.aging.model

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

/**
 * The person hub's features, each saying what it is *for* (`CareFeature` in
 * `CareOverview.swift`). A feature is not done until it has a case here and a
 * tile on the hub. The Android build carries the features it ports; the rest
 * are listed in the Android rule as not yet ported.
 */
enum class CareFeature(val title: String, val blurb: String) {
    MEDICATIONS("Medications", "Doses, times and refills"),
    VISITS("Appointments", "What's coming up, and what was said"),
    HEALTH_DETAILS("Health details", "Allergies, conditions, blood type"),
    CONTACTS("Contacts", "Who to call first"),
    PROVIDERS("Providers", "Doctors and pharmacies"),
}

object CareOverview {

    fun detail(feature: CareFeature, state: CareState, personId: UUID, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String {
        val person = state.person(personId) ?: return "None yet"
        return when (feature) {
            CareFeature.MEDICATIONS -> counted(state.activeMedications(personId).size, "medication", "medications")
            CareFeature.VISITS -> {
                val next = state.upcomingVisits(personId, now).firstOrNull()
                if (next != null) {
                    val day = next.date.atZone(zone).format(DateTimeFormatter.ofPattern("EEE d MMM"))
                    "Next: $day"
                } else counted(state.visitsOf(personId).size, "visit", "visits")
            }
            CareFeature.PROVIDERS -> state.providersOf(personId).size.let { if (it == 0) "None yet" else "$it saved" }
            CareFeature.HEALTH_DETAILS -> listOfNotNull(
                pluralized(person.allergies.size, "allergy", "allergies"),
                pluralized(person.conditions.size, "condition", "conditions"),
                if (person.bloodType.isEmpty()) null else "blood type",
            ).joinToString(", ").ifEmpty { "None yet" }
            CareFeature.CONTACTS -> counted(state.contactsOf(personId).size, "contact", "contacts")
        }
    }

    fun isEmpty(feature: CareFeature, state: CareState, personId: UUID): Boolean {
        val person = state.person(personId) ?: return true
        return when (feature) {
            CareFeature.MEDICATIONS -> state.activeMedications(personId).isEmpty()
            CareFeature.VISITS -> state.visitsOf(personId).isEmpty()
            CareFeature.PROVIDERS -> state.providersOf(personId).isEmpty()
            CareFeature.HEALTH_DETAILS -> person.allergies.isEmpty() && person.conditions.isEmpty() && person.bloodType.isEmpty()
            CareFeature.CONTACTS -> state.contactsOf(personId).isEmpty()
        }
    }

    private fun counted(n: Int, singular: String, plural: String) =
        if (n == 0) "None yet" else "$n ${if (n == 1) singular else plural}"

    private fun pluralized(n: Int, singular: String, plural: String): String? =
        if (n <= 0) null else "$n ${if (n == 1) singular else plural}"
}
