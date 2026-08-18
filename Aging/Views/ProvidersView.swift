import SwiftData
import SwiftUI

/// The provider list reachable from `PersonDetailView` (plan82 slice C). One
/// row per doctor, specialist, dentist, pharmacy or therapist, the shape a
/// paper list actually has instead of a name retyped on every medication.
struct ProvidersView: View {
    let person: Person

    @Environment(\.modelContext) private var context
    @Environment(GroupService.self) private var groups
    @State private var editingProvider: Provider?
    @State private var pendingDeletion: PendingRecordDeletion?
    @State private var isAddingProvider = false

    private var sortedProviders: [Provider] {
        person.liveProviders.sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            if sortedProviders.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No providers yet",
                        systemImage: "stethoscope",
                        description: Text("Add a doctor, specialist or pharmacy with a phone number.")
                    )
                }
            } else {
                Section {
                    ForEach(sortedProviders) { provider in
                        Button {
                            editingProvider = provider
                        } label: {
                            providerRow(provider)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: requestProviderDeletion)
                } footer: {
                    Text("Providers with a phone number appear on the emergency card.")
                }
            }
        }
        .navigationTitle("Providers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingProvider = true
                } label: {
                    Label("Add provider", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingProvider) {
            ProviderEditorSheet(person: person, provider: nil)
        }
        .sheet(item: $editingProvider) { provider in
            ProviderEditorSheet(person: person, provider: provider)
        }
        .recordDeletionConfirmation($pendingDeletion)
    }

    private func providerRow(_ provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(provider.name)
                    .font(.body.weight(.medium))
                if provider.isPharmacy {
                    Text("Pharmacy")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
            }
            let detail = [provider.specialty, provider.phone].filter { !$0.isEmpty }
            if !detail.isEmpty {
                Text(detail.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Detaches the provider from every medication and visit that pointed at
    /// it rather than deleting them: a provider is a shortcut to a phone
    /// number, and the record it was attached to is real data.
    private func deleteProviders(_ providers: [Provider]) {
        for provider in providers {
            provider.detachAndTombstone(in: context)
        }
    }

    private func requestProviderDeletion(at offsets: IndexSet) {
        let providers = sortedProviders
        let doomed = offsets.compactMap { providers.indices.contains($0) ? providers[$0] : nil }
        guard !doomed.isEmpty else { return }
        let name = doomed.count == 1 ? doomed[0].name : "\(doomed.count) providers"
        pendingDeletion = PendingRecordDeletion(
            title: doomed.count == 1 ? "Delete \(name)?" : "Delete \(doomed.count) providers?",
            // Says the reassuring half out loud: the medications and visits
            // that pointed here are not going anywhere.
            message: PendingRecordDeletion.message(
                "The phone number comes off the emergency card. Medications and visits that named \(doomed.count == 1 ? "them" : "them") are kept.",
                isShared: groups.activeGroupID != nil
            ),
            confirmLabel: "Delete",
            perform: { deleteProviders(doomed) }
        )
    }
}

struct ProviderEditorSheet: View {
    let person: Person
    let provider: Provider?
    /// Preselects "This is a pharmacy" when opened from the pharmacy slot of
    /// a picker, so adding a pharmacy inline does not require an extra tap.
    var defaultIsPharmacy: Bool = false
    /// Set by `ProviderPickerSheet` so a newly created provider is selected
    /// immediately, without a second trip back through the picker list.
    var onSave: ((UUID) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var specialty = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var portalURL = ""
    @State private var notes = ""
    @State private var isPharmacy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.organizationName)
                    Toggle("This is a pharmacy", isOn: $isPharmacy)
                    if !isPharmacy {
                        TextField("Specialty", text: $specialty)
                    }
                }

                Section {
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Address", text: $address, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Patient portal link", text: $portalURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        // Said where the decision is made, not only on the list
                        // afterwards. Someone adding a doctor "for emergencies"
                        // should find out here that a blank phone field is what
                        // keeps them off the card, not by looking for them on it.
                        if phone.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("Without a phone number this stays in your records and does not go on the emergency card.")
                        }
                        Text("The portal link is just a bookmark. Elderhub never stores a username or password.")
                    }
                }

                Section("Notes") {
                    TextField("Anything else worth knowing", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(provider == nil ? "Add Provider" : "Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let provider else {
                    isPharmacy = defaultIsPharmacy
                    return
                }
                name = provider.name
                specialty = provider.specialty
                phone = provider.phone
                address = provider.address
                portalURL = provider.portalURL
                notes = provider.notes
                isPharmacy = provider.isPharmacy
            }
        }
    }

    private func save() {
        let target = provider ?? {
            let new = Provider(name: "", person: person)
            context.insert(new)
            return new
        }()

        target.name = name.trimmingCharacters(in: .whitespaces)
        target.specialty = specialty.trimmingCharacters(in: .whitespaces)
        target.phone = phone.trimmingCharacters(in: .whitespaces)
        target.address = address.trimmingCharacters(in: .whitespaces)
        target.portalURL = portalURL.trimmingCharacters(in: .whitespaces)
        target.notes = notes.trimmingCharacters(in: .whitespaces)
        target.isPharmacy = isPharmacy
        target.recordLocalChange(in: context)

        onSave?(target.id)
        dismiss()
    }
}

// MARK: - Picker

/// A row for the medication and visit editors: shows the linked provider's
/// name (or "None") and opens a sheet to pick an existing one or add a new
/// one inline. `isPharmacy` filters which providers are offered, so the
/// prescriber slot never lists a pharmacy and vice versa.
struct ProviderPickerField: View {
    let title: String
    let person: Person
    let isPharmacy: Bool
    @Binding var selection: UUID?

    @State private var isPresentingPicker = false

    private var selectedName: String? {
        guard let selection else { return nil }
        return person.liveProviders.first(where: { $0.id == selection })?.name
    }

    var body: some View {
        Button {
            isPresentingPicker = true
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(selectedName ?? "None")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isPresentingPicker) {
            ProviderPickerSheet(
                person: person, isPharmacy: isPharmacy, title: title, selection: $selection
            )
        }
    }
}

private struct ProviderPickerSheet: View {
    let person: Person
    let isPharmacy: Bool
    let title: String
    @Binding var selection: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var isAddingProvider = false

    private var providers: [Provider] {
        person.liveProviders
            .filter { $0.isPharmacy == isPharmacy }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selection = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("None")
                                .foregroundStyle(.primary)
                            Spacer()
                            if selection == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }

                    ForEach(providers) { provider in
                        Button {
                            selection = provider.id
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.name)
                                        .foregroundStyle(.primary)
                                    if !provider.specialty.isEmpty {
                                        Text(provider.specialty)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selection == provider.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        isAddingProvider = true
                    } label: {
                        Label(
                            isPharmacy ? "Add new pharmacy" : "Add new provider",
                            systemImage: "plus"
                        )
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isAddingProvider) {
                ProviderEditorSheet(
                    person: person, provider: nil, defaultIsPharmacy: isPharmacy
                ) { newID in
                    selection = newID
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProvidersView(person: SampleData.previewPerson())
    }
    .modelContainer(SampleData.previewContainer())
}
