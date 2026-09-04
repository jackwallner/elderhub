import SwiftUI

/// The payoff screen. Big type, no chrome, works with no network, and shares as
/// plain text so it can go into a message, an email or a printout.
struct EmergencyCardView: View {
    let person: Person

    @Environment(DeviceModeService.self) private var deviceMode

    @State private var isEditingDetails = false

    private var summary: String {
        MedListExporter.plainText(for: person)
    }

    /// An empty card used to render as nothing but "Medications: none recorded",
    /// which read as a medications screen and left no clue that allergies,
    /// conditions and contacts were things you could fill in.
    private var isEmpty: Bool {
        person.allergies.isEmpty
            && person.conditions.isEmpty
            && person.liveContacts.isEmpty
            && person.bloodType.isEmpty
            && person.activeMedications.isEmpty
            // Counted too, now that the empty prompt replaces the sections
            // rather than sitting above them: a card holding nothing but a
            // doctor's number should still print the number.
            && providersWithPhone.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                // The prompt used to *replace* the sections, on the reasoning
                // that repeating "Not recorded" five times would bury the
                // button that fixes it. That is true of Sarah setting the card
                // up and wrong of the only reader who matters: a clinician
                // handed a card carrying nothing but "Nothing on the card yet"
                // cannot tell an app that was never filled in from a patient
                // with no allergies and no medications. Both now, prompt first,
                // so the button is still the first thing Sarah sees and the
                // page still says what it does and does not know.
                if isEmpty, deviceMode.allowsEditing {
                    emptyPrompt
                }

                // Every critical section is drawn whether or not it has
                // content. A card that simply omits Allergies reads, to someone
                // holding it in an ER, as "no allergies"; there is no way to
                // tell an absent section from a negative answer, and the two
                // are very different facts. "Not recorded" says which one this
                // is.
                block(title: "Allergies", lines: person.allergies, tint: .red)
                block(title: "Conditions", lines: person.conditions, tint: .orange)

                medications

                contactsBlock

                if !providersWithPhone.isEmpty {
                    providersBlock
                }

                Text("This list is maintained by a family member and is not a medical record.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(20)
        }
        .navigationTitle("Emergency Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: summary) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            // Gone while the phone is handed over. This is the one editing
            // affordance reachable from the recipient's screen, and Settings
            // promises them that nothing there can be changed. Sharing stays:
            // reading the card out and sending it are the same act.
            if deviceMode.allowsEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { isEditingDetails = true }
                }
            }
        }
        .sheet(isPresented: $isEditingDetails) {
            PersonDetailsEditorSheet(person: person)
        }
    }

    private var sortedContacts: [EmergencyContact] {
        person.liveContacts.sorted {
            $0.isPrimary != $1.isPrimary ? $0.isPrimary : $0.name < $1.name
        }
    }

    /// Doctors, specialists and pharmacies with a phone number on file,
    /// shown under emergency contacts and tappable to call. A provider with
    /// no phone number has nothing useful to add to this card.
    private var providersWithPhone: [Provider] {
        person.liveProviders
            .filter { !$0.phone.isEmpty }
            .sorted { $0.name < $1.name }
    }

    /// Contacts, each one a tappable call. This is the block whose whole job is
    /// "who do I ring", and it was the one block on the card that was not a
    /// link: providers were callable and the daughter listed first was not.
    private var contactsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Emergency contacts")
                .font(.headline)
                .foregroundStyle(.blue)

            if sortedContacts.isEmpty {
                notRecorded
            } else {
                ForEach(sortedContacts) { contact in
                    if let url = telURL(for: contact.phone) {
                        Link(destination: url) {
                            contactLine(contact)
                        }
                    } else {
                        contactLine(contact)
                    }
                }
            }
        }
    }

    /// One contact, with "Call first" said out loud rather than implied by the
    /// order.
    ///
    /// The primary contact was sorted to the top of this block and marked
    /// nowhere, so the one fact the family recorded, "ring this person before
    /// the others", did not survive onto the page. Position is not a signal a
    /// stranger can read: somebody holding this card in an ER has no reason to
    /// believe the list is ordered at all, and with three names on it they
    /// pick one. The badge is the label, not the colour, so it still reads in
    /// mono, at any Dynamic Type size, and printed.
    private func contactLine(_ contact: EmergencyContact) -> some View {
        let who = contact.relationship.isEmpty
            ? contact.name
            : "\(contact.name) (\(contact.relationship))"
        // A "call first" contact with no number on file is worse than useless
        // in silence, because the card still presents them as the answer.
        let phone = contact.phone.isEmpty ? "no phone number saved" : contact.phone

        return VStack(alignment: .leading, spacing: 3) {
            if contact.isPrimary {
                Text("CALL FIRST")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red, in: Capsule())
            }
            Text("\(who), \(phone)")
                .font(.title3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Read as one sentence rather than as a loose "call first" followed by
        // a name, which is how VoiceOver announced the two Texts separately.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            contact.isPrimary
            ? "Call first. \(who), \(phone)"
            : "\(who), \(phone)"
        )
    }

    private var notRecorded: some View {
        Text("Not recorded")
            .font(.title3)
            .foregroundStyle(.secondary)
    }

    private var providersBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Providers")
                .font(.headline)
                .foregroundStyle(.blue)
            ForEach(providersWithPhone) { provider in
                if let url = telURL(for: provider.phone) {
                    Link(destination: url) {
                        providerLine(provider)
                    }
                } else {
                    providerLine(provider)
                }
            }
        }
    }

    private func providerLine(_ provider: Provider) -> some View {
        let label = provider.specialty.isEmpty ? provider.name : "\(provider.name) (\(provider.specialty))"
        return Text("\(label), \(provider.phone)")
            .font(.title3)
    }

    /// The number to dial, stopping at an extension rather than swallowing it.
    ///
    /// Keeping every digit in the string looks harmless until somebody has
    /// typed "555-1234 x203": the filter turned that into 5551234203 and the
    /// card offered to dial a number nobody has. On this screen a wrong number
    /// is not a cosmetic bug, so anything past the extension marker is dropped
    /// and the extension stays visible in the text beside it for a human to
    /// dial.
    private func telURL(for phone: String) -> URL? {
        let dialable = phone.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: "x#,;"))
            .first ?? phone
        let digits = dialable.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    private var emptyPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing on the card yet")
                .font(.title3.weight(.semibold))
            Text("Add allergies, conditions, blood type and who to call. This is the page you hand to a paramedic.")
                .foregroundStyle(.secondary)
            if deviceMode.allowsEditing {
                Button {
                    isEditingDetails = true
                } label: {
                    Label("Add details", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(person.name)
                .font(.largeTitle.bold())
                // Read by `OfflineLaunchUITests`: proving the card rendered is
                // not enough, it has to have carried real local data onto it.
                .accessibilityIdentifier("emergency-card.name")

            // Onboarding tells the person entering it that a date of birth
            // "prints on the emergency card", and it did not: the header showed
            // an age, which is not what a hospital asks for and is not a value
            // anybody can match a page to a patient with. Named when missing,
            // like the blood type below.
            Text(birthLine)
                .font(.title3)
                .foregroundStyle(.secondary)

            // Named even when it is missing, for the same reason the sections
            // below are: a blank where a blood type would be does not tell a
            // reader whether it is unknown or simply not here.
            Text(person.bloodType.isEmpty ? "Blood type not recorded" : "Blood type \(person.bloodType)")
                .font(.title3)
                .foregroundStyle(.secondary)

            // The exported one-pager prints when it was generated and the live
            // card printed nothing, so of the two routes to the same
            // information only one told the reader how old it might be. This is
            // the record's own last edit, not the time the screen was opened:
            // a card rendered a second ago from a record nobody has touched
            // since March is three months old, and saying "now" would be a
            // worse answer than saying nothing.
            Text(freshnessLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var birthLine: String {
        guard let birthDate = person.birthDate else { return "Date of birth not recorded" }
        let born = birthDate.formatted(date: .abbreviated, time: .omitted)
        guard let age = person.age else { return "Born \(born)" }
        return "Born \(born) · Age \(age)"
    }

    /// The most recent edit anywhere on the card: the person's own details, the
    /// medications it prints, the contacts it lists or the providers behind
    /// them. Whichever is newest is the honest answer to "how current is this".
    private var freshnessLine: String {
        var latest = person.updatedAt
        for medication in person.activeMedications { latest = max(latest, medication.updatedAt) }
        for contact in person.liveContacts { latest = max(latest, contact.updatedAt) }
        for provider in providersWithPhone { latest = max(latest, provider.updatedAt) }
        return "Last updated \(latest.formatted(date: .abbreviated, time: .shortened))"
    }

    private var medications: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Medications")
                .font(.headline)
                .foregroundStyle(.green)

            if person.activeMedications.isEmpty {
                Text("None recorded")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(person.activeMedications) { med in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(med.displayName)
                            .font(.title3.weight(.medium))
                        if !detail(for: med).isEmpty {
                            Text(detail(for: med))
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// Deliberately the same fields as `MedListExporter.line(for:)`, in the
    /// same order.
    ///
    /// The card carried name, schedule and purpose while the exported one-pager
    /// carried form, instructions, prescriber and pharmacy as well, so Sarah
    /// showing a clinician the screen believed she was handing over the page
    /// she would have sent them. Two routes to "the emergency information",
    /// with different information on them, is a route-dependent handoff.
    private func detail(for med: Medication) -> String {
        var parts: [String] = []
        if med.isAsNeeded {
            parts.append("As needed")
        } else if !med.scheduleLabel.isEmpty {
            // "Mondays · 8:00 AM". A weekly tablet that reads as a daily one is
            // the worst thing this card can say.
            parts.append(med.scheduleLabel)
        }
        if !med.form.rawValue.isEmpty, med.form != .other {
            parts.append(med.form.label.lowercased())
        }
        if !med.purpose.isEmpty {
            parts.append("for \(med.purpose)")
        }
        if !med.instructions.isEmpty {
            parts.append(med.instructions)
        }
        let prescriber = med.resolvedPrescriberName
        if !prescriber.isEmpty {
            let phone = med.resolvedPrescriberPhone
            parts.append(phone.isEmpty ? "(\(prescriber))" : "(\(prescriber), \(phone))")
        }
        let pharmacy = med.resolvedPharmacyName
        if !pharmacy.isEmpty {
            let phone = med.resolvedPharmacyPhone
            parts.append(phone.isEmpty ? "pharmacy: \(pharmacy)" : "pharmacy: \(pharmacy), \(phone)")
        }
        return parts.joined(separator: " · ")
    }

    private func block(title: String, lines: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(tint)
            if lines.isEmpty {
                notRecorded
            } else {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.title3)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        EmergencyCardView(person: SampleData.previewPerson())
    }
    .modelContainer(SampleData.previewContainer())
    .environment(DeviceModeService.shared)
}
