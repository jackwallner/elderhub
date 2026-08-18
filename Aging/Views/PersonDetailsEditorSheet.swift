import SwiftData
import SwiftUI

/// The health details on the emergency card that are not medications or
/// emergency contacts.
///
/// Emergency contacts have their own destination so that they are not hidden
/// behind a combined "allergies, conditions, contacts" label.
struct PersonDetailsEditorSheet: View {
    let person: Person

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name: String
    @State private var relationship: String
    @State private var isSelf: Bool
    @State private var hasBirthDate: Bool
    @State private var birthDate: Date
    @State private var bloodType: String
    @State private var allergies: [String]
    @State private var conditions: [String]
    @State private var notes: String

    @State private var newAllergy = ""
    @State private var newCondition = ""
    private static let bloodTypes = ["", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]

    init(person: Person) {
        self.person = person
        _name = State(initialValue: person.name)
        _relationship = State(initialValue: person.relationship)
        _isSelf = State(initialValue: person.isSelf)
        _hasBirthDate = State(initialValue: person.birthDate != nil)
        _birthDate = State(
            initialValue: person.birthDate
                ?? Calendar.current.date(byAdding: .year, value: -75, to: Date())
                ?? Date()
        )
        _bloodType = State(initialValue: person.bloodType)
        _allergies = State(initialValue: person.allergies)
        _conditions = State(initialValue: person.conditions)
        _notes = State(initialValue: person.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Relationship (Mom, Dad, Me)", text: $relationship)
                } footer: {
                    Text("The name is what every screen calls this record. The relationship is the subtitle under it.")
                }

                // Switchable, because it is a thing people get wrong on the
                // first screen of the app and then cannot correct. Someone who
                // started a record "for Mom" and is now also tracking
                // themselves, or who tapped "Keep track of myself" by mistake,
                // had no way to say so: `isSelf` was written once during
                // onboarding and never offered again.
                Section {
                    Toggle("This record is about me", isOn: $isSelf)
                } footer: {
                    Text(isSelf
                         ? "Your own record. The daily check-in, when it is set up, is yours to press."
                         : "A record you keep for someone else. They can be invited to press their own check-in.")
                }

                Section {
                    Toggle("Date of birth", isOn: $hasBirthDate)
                    if hasBirthDate {
                        DatePicker("Born", selection: $birthDate, displayedComponents: .date)
                    }
                    Picker("Blood type", selection: $bloodType) {
                        ForEach(Self.bloodTypes, id: \.self) { type in
                            Text(type.isEmpty ? "Not known" : type).tag(type)
                        }
                    }
                }

                // Allergies lead the emergency card and are the first thing a
                // paramedic asks for, so they get their own section rather than
                // being one line in a notes field.
                // The placeholder says it is an example. Bare "Penicillin"
                // sitting under a list that already contains entries reads as
                // a value that is somehow already there, and the question
                // "should I retype this?" is not one an allergy field should
                // ever raise.
                listSection(
                    title: "Allergies",
                    footer: "Shown first on the emergency card.",
                    items: $allergies,
                    draft: $newAllergy,
                    placeholder: "Add an allergy (e.g. penicillin)"
                )

                listSection(
                    title: "Conditions",
                    footer: nil,
                    items: $conditions,
                    draft: $newCondition,
                    placeholder: "Add a condition (e.g. type 2 diabetes)"
                )

                Section("Emergency contacts") {
                    NavigationLink {
                        EmergencyContactsView(person: person)
                    } label: {
                        Label(
                            person.liveContacts.isEmpty ? "Add emergency contact" : "Manage emergency contacts",
                            systemImage: "person.2"
                        )
                    }
                }

                Section("Notes") {
                    TextField("Anything else worth knowing", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Details")
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
        }
    }

    @ViewBuilder
    private func listSection(
        title: String,
        footer: String?,
        items: Binding<[String]>,
        draft: Binding<String>,
        placeholder: String
    ) -> some View {
        Section {
            ForEach(items.wrappedValue, id: \.self) { item in
                Text(item)
            }
            .onDelete { offsets in
                items.wrappedValue.remove(atOffsets: offsets)
            }

            HStack {
                // Drug and condition names are not dictionary words, and
                // autocorrect turning "Losartan" into "Loosen" on an allergy
                // line is the one typo here that could matter.
                TextField(placeholder, text: draft)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .onSubmit { commit(draft: draft, into: items) }
                Button {
                    commit(draft: draft, into: items)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text(title)
        } footer: {
            if let footer { Text(footer) }
        }
    }

    private func commit(draft: Binding<String>, into items: Binding<[String]>) {
        let value = draft.wrappedValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !items.wrappedValue.contains(value) else { return }
        items.wrappedValue.append(value)
        draft.wrappedValue = ""
    }

    private func save() {
        // A draft left in the text field is an entry the user typed and expects
        // to keep. Dropping it on Save is the classic version of this bug.
        commit(draft: $newAllergy, into: $allergies)
        commit(draft: $newCondition, into: $conditions)

        person.name = name.trimmingCharacters(in: .whitespaces)
        person.relationship = relationship.trimmingCharacters(in: .whitespaces)
        person.isSelf = isSelf
        person.birthDate = hasBirthDate ? birthDate : nil
        person.bloodType = bloodType
        person.allergies = allergies
        person.conditions = conditions
        person.notes = notes.trimmingCharacters(in: .whitespaces)
        person.recordLocalChange(in: context)
        dismiss()
    }
}

/// Emergency contacts are a first-class destination because they are useful
/// on their own and are not another kind of allergy or condition.
struct EmergencyContactsView: View {
    let person: Person

    @Environment(\.modelContext) private var context

    @State private var editingContact: EmergencyContact?
    @State private var isAddingContact = false
    @State private var pendingDeletion: EmergencyContact?

    var body: some View {
        List {
            if sortedContacts.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No emergency contacts",
                        systemImage: "person.2",
                        description: Text("Add someone your family can call first.")
                    )
                }
            } else {
                Section {
                    ForEach(sortedContacts) { contact in
                        Button {
                            editingContact = contact
                        } label: {
                            contactRow(contact)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteContacts)
                } footer: {
                    Text("The primary contact is listed first on the emergency card.")
                }
            }
        }
        .navigationTitle("Emergency Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingContact = true
                } label: {
                    Label("Add contact", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingContact) {
            EmergencyContactEditorSheet(person: person, contact: nil)
        }
        .sheet(item: $editingContact) { contact in
            EmergencyContactEditorSheet(person: person, contact: contact)
        }
        .confirmationDialog(
            pendingDeletion.map { "Remove \($0.name)?" } ?? "Remove this contact?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                pendingDeletion?.tombstone(in: context)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            // Worth a question, unlike an ordinary list row: this is the number
            // somebody reads off the emergency card in the worst ten minutes of
            // the year, and a stray swipe removes it silently.
            Text("They come off the emergency card straight away.")
        }
    }

    private var sortedContacts: [EmergencyContact] {
        person.liveContacts.sorted {
            $0.isPrimary != $1.isPrimary ? $0.isPrimary : $0.name < $1.name
        }
    }

    private func contactRow(_ contact: EmergencyContact) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(contact.name)
                    .font(.body.weight(.medium))
                if contact.isPrimary {
                    Text("Primary")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                }
            }
            Text([contact.relationship, contact.phone.isEmpty ? "No phone number" : contact.phone]
                .filter { !$0.isEmpty }
                .joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(contact.phone.isEmpty ? .orange : .secondary)
        }
        .padding(.vertical, 4)
    }

    private func deleteContacts(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        pendingDeletion = sortedContacts[index]
    }
}

struct EmergencyContactEditorSheet: View {
    let person: Person
    let contact: EmergencyContact?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var relationship = ""
    @State private var phone = ""
    @State private var isPrimary = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Relationship (Daughter, Neighbor)", text: $relationship)
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                } footer: {
                    // Stated rather than enforced. A contact with a name and no
                    // number is still worth having on the card; what is not
                    // acceptable is the user not realising that the tap-to-call
                    // they expect will not be there.
                    if phone.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Without a number they are still listed on the emergency card, but nobody can call them from it.")
                    }
                }

                Section {
                    Toggle("Call this person first", isOn: $isPrimary)
                } footer: {
                    Text("Listed at the top of the emergency card.")
                }
            }
            .navigationTitle(contact == nil ? "Add Contact" : "Contact")
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
                guard let contact else { return }
                name = contact.name
                relationship = contact.relationship
                phone = contact.phone
                isPrimary = contact.isPrimary
            }
        }
    }

    private func save() {
        let target = contact ?? {
            let new = EmergencyContact(name: "", person: person)
            context.insert(new)
            return new
        }()

        target.name = name.trimmingCharacters(in: .whitespaces)
        target.relationship = relationship.trimmingCharacters(in: .whitespaces)
        target.phone = phone.trimmingCharacters(in: .whitespaces)
        target.isPrimary = isPrimary
        target.recordLocalChange(in: context)

        // Exactly one contact can be first. Setting a new one demotes the old.
        if isPrimary {
            for other in person.liveContacts where other.id != target.id && other.isPrimary {
                other.isPrimary = false
                other.recordLocalChange(in: context)
            }
        }

        dismiss()
    }
}

#Preview {
    PersonDetailsEditorSheet(person: SampleData.previewPerson())
        .modelContainer(SampleData.previewContainer())
}
