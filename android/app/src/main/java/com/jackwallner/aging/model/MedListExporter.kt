package com.jackwallner.aging.model

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import java.util.UUID

/**
 * Port of `MedListExporter.swift`: the plain-text one-pager shared from the
 * emergency card. Every critical section prints even when empty, so a reader
 * can tell "none" from "nobody wrote it down". Keep in step with the card.
 */
object MedListExporter {
    const val DISCLAIMER = "This list is maintained by a family member and is not a medical record."

    fun plainText(
        state: CareState,
        personId: UUID,
        generatedAt: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
        locale: Locale = Locale.getDefault(),
    ): String {
        val person = state.person(personId) ?: return ""
        val lines = mutableListOf<String>()
        val dateFormat = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale)
        val stampFormat = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(locale)

        lines += "MEDICATION LIST: ${person.name}"
        lines += person.birthDate?.let { "Date of birth: ${it.format(dateFormat)}" } ?: "Date of birth: not recorded"
        person.age(generatedAt.atZone(zone).toLocalDate())?.let { lines += "Age $it" }
        lines += "Blood type: ${person.bloodType.ifEmpty { "not recorded" }}"
        lines += "Generated ${generatedAt.atZone(zone).format(stampFormat)}"
        lines += ""

        lines += "ALLERGIES: ${if (person.allergies.isEmpty()) "not recorded" else person.allergies.joinToString(", ")}"
        lines += ""
        lines += "CONDITIONS: ${if (person.conditions.isEmpty()) "not recorded" else person.conditions.joinToString(", ")}"
        lines += ""

        val active = state.activeMedications(personId)
        val scheduled = active.filter { !it.isAsNeeded }
        val asNeeded = active.filter { it.isAsNeeded }
        if (scheduled.isNotEmpty()) {
            lines += "SCHEDULED MEDICATIONS"
            scheduled.forEach { lines += line(state, it) }
            lines += ""
        }
        if (asNeeded.isNotEmpty()) {
            lines += "AS NEEDED"
            asNeeded.forEach { lines += line(state, it) }
            lines += ""
        }
        if (active.isEmpty()) {
            lines += "No active medications recorded."
            lines += ""
        }

        val contacts = state.contactsOf(personId)
        lines += "EMERGENCY CONTACTS"
        if (contacts.isEmpty()) {
            lines += "  Not recorded"
        } else {
            for (contact in contacts) {
                val relationship = if (contact.relationship.isEmpty()) "" else " (${contact.relationship})"
                val phone = contact.phone.ifEmpty { "no phone number saved" }
                val marker = if (contact.isPrimary) "CALL FIRST: " else ""
                lines += "  $marker${contact.name}$relationship, $phone"
            }
        }
        lines += ""

        val providers = state.providersOf(personId).filter { it.phone.isNotEmpty() }
        if (providers.isNotEmpty()) {
            lines += "PROVIDERS"
            for (provider in providers) {
                val specialty = if (provider.specialty.isEmpty()) "" else " (${provider.specialty})"
                lines += "  ${provider.name}$specialty, ${provider.phone}"
            }
            lines += ""
        }

        lines += DISCLAIMER
        return lines.joinToString("\n")
    }

    private fun line(state: CareState, med: Medication): String {
        val parts = mutableListOf("  ${med.displayName}")
        if (med.form != MedicationForm.OTHER) parts += med.form.label.lowercase()
        med.scheduleLabel().takeIf { it.isNotEmpty() }?.let { parts += it }
        if (med.purpose.isNotEmpty()) parts += "for ${med.purpose}"
        if (med.instructions.isNotEmpty()) parts += med.instructions

        val prescriber = state.provider(med.providerId)
        val prescriberName = prescriber?.name ?: med.prescriber
        if (prescriberName.isNotEmpty()) {
            val phone = prescriber?.phone.orEmpty()
            parts += if (phone.isEmpty()) "($prescriberName)" else "($prescriberName, $phone)"
        }
        val pharmacy = state.provider(med.pharmacyId)
        val pharmacyName = pharmacy?.name ?: med.pharmacy
        if (pharmacyName.isNotEmpty()) {
            val phone = pharmacy?.phone.orEmpty()
            parts += if (phone.isEmpty()) "pharmacy: $pharmacyName" else "pharmacy: $pharmacyName, $phone"
        }
        return parts.joinToString(" · ")
    }
}
