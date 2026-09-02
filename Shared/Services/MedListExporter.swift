import Foundation

/// Builds the one-page medication summary. This is the feature that earns the app:
/// the thing a family actually needs is a current, correct list they can hand to an
/// ER nurse or a new specialist without reciting it from memory.
enum MedListExporter {

    @MainActor
    static func plainText(for person: Person, generatedAt: Date = Date()) -> String {
        var lines: [String] = []

        lines.append("MEDICATION LIST: \(person.name)")
        if let age = person.age {
            lines.append("Age \(age)")
        }
        // Printed even when empty, matching the emergency card's header and the
        // ALLERGIES/CONDITIONS rule below: a sheet with no blood-type line at
        // all reads as "nobody needs one", not as "nobody wrote it down".
        lines.append("Blood type: \(person.bloodType.isEmpty ? "not recorded" : person.bloodType)")
        lines.append("Generated \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
        lines.append("")

        // Always printed, even empty, and for the same reason the card always
        // draws them: a one-pager that silently leaves out ALLERGIES lets the
        // reader assume there are none. The sheet has to distinguish "none"
        // from "nobody wrote it down".
        lines.append("ALLERGIES: \(person.allergies.isEmpty ? "not recorded" : person.allergies.joined(separator: ", "))")
        lines.append("")
        lines.append("CONDITIONS: \(person.conditions.isEmpty ? "not recorded" : person.conditions.joined(separator: ", "))")
        lines.append("")

        let scheduled = person.activeMedications.filter { !$0.isAsNeeded }
        let asNeeded = person.activeMedications.filter(\.isAsNeeded)

        if !scheduled.isEmpty {
            lines.append("SCHEDULED MEDICATIONS")
            for med in scheduled {
                lines.append(line(for: med))
            }
            lines.append("")
        }

        if !asNeeded.isEmpty {
            lines.append("AS NEEDED")
            for med in asNeeded {
                lines.append(line(for: med))
            }
            lines.append("")
        }

        if person.activeMedications.isEmpty {
            lines.append("No active medications recorded.")
            lines.append("")
        }

        // Primary first, then alphabetical. The previous predicate was not a
        // strict weak ordering (it returns false both ways for two non-primary
        // contacts), which `sorted` is entitled to make a mess of.
        let contacts = person.liveContacts.sorted {
            $0.isPrimary != $1.isPrimary ? $0.isPrimary : $0.name < $1.name
        }
        lines.append("EMERGENCY CONTACTS")
        if contacts.isEmpty {
            lines.append("  Not recorded")
        } else {
            for contact in contacts {
                let relationship = contact.relationship.isEmpty ? "" : " (\(contact.relationship))"
                let phone = contact.phone.isEmpty ? "no phone number saved" : contact.phone
                // Said, not implied by position. This text is read off a
                // printout or a message by someone who has never seen the app
                // and has no reason to think the list is in any order, so the
                // family's "ring her first" has to be on the line itself. The
                // marker leads the line because that is the column a reader
                // scans down.
                let marker = contact.isPrimary ? "CALL FIRST: " : ""
                lines.append("  \(marker)\(contact.name)\(relationship), \(phone)")
            }
        }
        lines.append("")

        // The card shows every provider with a phone number on file, and the
        // sheet used not to. Someone who shares what they believe is the same
        // page should not find the doctor's number missing from it.
        let providers = person.liveProviders
            .filter { !$0.phone.isEmpty }
            .sorted { $0.name < $1.name }
        if !providers.isEmpty {
            lines.append("PROVIDERS")
            for provider in providers {
                let specialty = provider.specialty.isEmpty ? "" : " (\(provider.specialty))"
                lines.append("  \(provider.name)\(specialty), \(provider.phone)")
            }
            lines.append("")
        }

        lines.append("This list is maintained by a family member and is not a medical record.")

        return lines.joined(separator: "\n")
    }

    @MainActor
    private static func line(for med: Medication) -> String {
        var parts = ["  \(med.displayName)"]

        if !med.form.rawValue.isEmpty, med.form != .other {
            parts.append(med.form.label.lowercased())
        }
        // Days and times both, from the one place all three renderings of a
        // schedule now come from.
        if !med.scheduleLabel.isEmpty {
            parts.append(med.scheduleLabel)
        }
        if !med.purpose.isEmpty {
            parts.append("for \(med.purpose)")
        }
        if !med.instructions.isEmpty {
            parts.append(med.instructions)
        }

        // A phone number here is the payoff of linking a provider: the person
        // holding this list can call the prescriber or the pharmacy without
        // hunting for a number first.
        let prescriberName = med.resolvedPrescriberName
        if !prescriberName.isEmpty {
            let phone = med.resolvedPrescriberPhone
            parts.append(phone.isEmpty ? "(\(prescriberName))" : "(\(prescriberName), \(phone))")
        }

        let pharmacyName = med.resolvedPharmacyName
        if !pharmacyName.isEmpty {
            let phone = med.resolvedPharmacyPhone
            parts.append(phone.isEmpty ? "pharmacy: \(pharmacyName)" : "pharmacy: \(pharmacyName), \(phone)")
        }

        return parts.joined(separator: " · ")
    }
}
