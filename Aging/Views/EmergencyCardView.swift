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

                if isEmpty {
                    // Nothing at all: the prompt says what to fill in, and
                    // repeating "Not recorded" five times below it would only
                    // bury the one button that fixes the situation.
                    emptyPrompt
                } else {
                    // Once the card holds anything, every critical section is
                    // drawn whether or not it has content. A card that simply
                    // omits Allergies reads, to someone holding it in an ER, as
                    // "no allergies"; there is no way to tell an absent section
                    // from a negative answer, and the two are very different
                    // facts. "Not recorded" says which one this is.
                    block(title: "Allergies", lines: person.allergies, tint: .red)
                    block(title: "Conditions", lines: person.conditions, tint: .orange)

                    medications

                    contactsBlock

                    if !providersWithPhone.isEmpty {
                        providersBlock
                    }
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

    private func contactLine(_ contact: EmergencyContact) -> some View {
        let who = contact.relationship.isEmpty
            ? contact.name
            : "\(contact.name) (\(contact.relationship))"
        // A "call first" contact with no number on file is worse than useless
        // in silence, because the card still presents them as the answer.
        let phone = contact.phone.isEmpty ? "no phone number saved" : contact.phone
        return Text("\(who), \(phone)")
            .font(.title3)
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

    private func telURL(for phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
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

            HStack(spacing: 8) {
                if let age = person.age {
                    Text("Age \(age)")
                    Text("·")
                }
                // Named even when it is missing, for the same reason the
                // sections below are: a blank where a blood type would be does
                // not tell a reader whether it is unknown or simply not here.
                Text(person.bloodType.isEmpty ? "Blood type not recorded" : "Blood type \(person.bloodType)")
            }
            .font(.title3)
            .foregroundStyle(.secondary)
        }
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

    private func detail(for med: Medication) -> String {
        var parts: [String] = []
        if med.isAsNeeded {
            parts.append("As needed")
        } else if !med.scheduleMinutes.isEmpty {
            parts.append(
                med.scheduleMinutes.sorted()
                    .map { ScheduleEngine.timeLabel(forMinutes: $0) }
                    .joined(separator: ", ")
            )
        }
        if !med.purpose.isEmpty {
            parts.append("for \(med.purpose)")
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
