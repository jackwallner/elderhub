import SwiftData
import SwiftUI

/// The long version of setting a record up: date of birth, allergies,
/// conditions, blood type, a contact, a medication, a doctor and a pharmacy,
/// dose reminders, and the family.
///
/// Every step skips. That is not a courtesy, it is what makes a flow this long
/// safe to put in front of someone on the day their mother came out of
/// hospital: they can answer the two questions they know and get to the app.
/// Nothing is lost by skipping, because the same steps reappear as rows on the
/// Today checklist, and `SettingsView` can re-run the whole thing.
///
/// Reachable twice: once at the end of first launch, and again from Settings →
/// "Set up again", which is why it takes a `Person` rather than creating one.
struct OnboardingDetailsFlow: View {
    let person: Person
    /// "Continue" on the last step. The caller decides whether that means
    /// finishing onboarding or dismissing a sheet.
    let onFinished: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth

    enum Step: Int, CaseIterable {
        case birthDate
        case allergies
        case conditions
        case contact
        case medication
        case providers
        case reminders
        case family
    }

    @State private var index = 0

    // Answers held locally and written on Continue, so a Skip leaves the record
    // exactly as it was rather than saving a default nobody typed.
    @State private var hasBirthDate = false
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -75, to: Date()) ?? Date()
    @State private var allergies: [String] = []
    @State private var newAllergy = ""
    @State private var conditions: [String] = []
    @State private var newCondition = ""
    @State private var bloodType = ""

    @State private var isAddingContact = false
    @State private var isAddingMedication = false
    @State private var isAddingProvider = false
    @State private var isAddingPharmacy = false
    @State private var isInviting = false
    @State private var remindersOn = false

    private static let bloodTypes = ["", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]

    private var step: Step { Step(rawValue: index) ?? .family }
    private var isLast: Bool { index >= Step.allCases.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            progress

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    heading
                    stepBody(for: step)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }

            footer
        }
        .sheet(isPresented: $isAddingContact) {
            EmergencyContactEditorSheet(person: person, contact: nil)
        }
        .sheet(isPresented: $isAddingMedication) {
            MedicationEditorSheet(person: person)
        }
        .sheet(isPresented: $isAddingProvider) {
            ProviderEditorSheet(person: person, provider: nil)
        }
        .sheet(isPresented: $isAddingPharmacy) {
            ProviderEditorSheet(person: person, provider: nil, defaultIsPharmacy: true)
        }
        .sheet(isPresented: $isInviting) {
            InviteSheet(people: [person])
        }
        .onAppear(perform: load)
    }

    // MARK: - Chrome

    private var progress: some View {
        VStack(spacing: 10) {
            ProgressView(value: Double(index + 1), total: Double(Step.allCases.count))
                .tint(.accentColor)
            HStack {
                Text("Step \(index + 1) of \(Step.allCases.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if index > 0 {
                    Button("Back") { index -= 1 }
                        .font(.footnote)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title(for: step))
                .font(.title2.bold())
                .multilineTextAlignment(.leading)
            Text(detail(for: step))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Skip and Continue are the same size and in the same place on every step,
    /// and the footer reserves its height whether or not the step has anything
    /// to save. A layout that shifts as the answer changes is the one thing
    /// guaranteed to make someone tap the wrong one.
    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                advance(saving: true)
            } label: {
                Text(isLast ? "Done" : "Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("onboarding.details.continue")

            Button(isLast ? "Finish without this" : "Skip this step") {
                advance(saving: false)
            }
            .font(.body)
            .frame(height: 28)
            .accessibilityIdentifier("onboarding.details.skip")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .background(.bar)
    }

    // MARK: - Copy

    private var who: String { person.displayLabel }

    private func title(for step: Step) -> String {
        switch step {
        case .birthDate: return "When was \(who) born?"
        case .allergies: return "Any allergies?"
        case .conditions: return "Any ongoing conditions?"
        case .contact: return "Who should be called first?"
        case .medication: return "Add the first medication"
        case .providers: return "Doctor and pharmacy"
        case .reminders: return "Reminders"
        case .family: return "Anyone else helping?"
        }
    }

    private func detail(for step: Step) -> String {
        switch step {
        case .birthDate:
            return "A date of birth is the first thing a hospital asks for. It prints on the emergency card."
        case .allergies:
            return "Allergies lead the emergency card and are the first question a paramedic asks."
        case .conditions:
            return "Conditions and blood type, if you know them. Both print on the emergency card."
        case .contact:
            return "One number your family can call first. It sits at the top of the emergency card."
        case .medication:
            return "Name, strength and the times it is taken. Doses then appear on Today, ready to tick off."
        case .providers:
            return "The surgery and the pharmacy, so nobody has to look up a number twice."
        case .reminders:
            return "This phone buzzes at each dose time for \(who), and the evening before an appointment. Each phone is set separately."
        case .family:
            return "A brother, sister or partner sees the same record on their own phone. Helpers are free."
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private func stepBody(for step: Step) -> some View {
        switch step {
        case .birthDate:
            VStack(alignment: .leading, spacing: 12) {
                Toggle("I know the date of birth", isOn: $hasBirthDate)
                    .font(.body)
                if hasBirthDate {
                    DatePicker("Born", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
            }

        case .allergies:
            entryList(
                items: $allergies,
                draft: $newAllergy,
                placeholder: "Add an allergy (e.g. penicillin)",
                empty: "No allergies recorded yet."
            )

        case .conditions:
            VStack(alignment: .leading, spacing: 20) {
                entryList(
                    items: $conditions,
                    draft: $newCondition,
                    placeholder: "Add a condition (e.g. type 2 diabetes)",
                    empty: "No conditions recorded yet."
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text("Blood type")
                        .font(.headline)
                    Picker("Blood type", selection: $bloodType) {
                        ForEach(Self.bloodTypes, id: \.self) { type in
                            Text(type.isEmpty ? "Not known" : type).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

        case .contact:
            addedList(
                count: person.liveContacts.count,
                noun: "contact",
                addLabel: "Add an emergency contact",
                symbol: "phone.fill",
                rows: person.liveContacts.map { contact in
                    [contact.name, contact.relationship, contact.phone]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                }
            ) { isAddingContact = true }

        case .medication:
            addedList(
                count: person.activeMedications.count,
                noun: "medication",
                addLabel: "Add a medication",
                symbol: "pills.fill",
                rows: person.activeMedications.map(\.displayName)
            ) { isAddingMedication = true }

        case .providers:
            VStack(alignment: .leading, spacing: 16) {
                addedList(
                    count: person.liveProviders.filter { !$0.isPharmacy }.count,
                    noun: "doctor",
                    addLabel: "Add a doctor",
                    symbol: "stethoscope",
                    rows: person.liveProviders.filter { !$0.isPharmacy }.map(\.name)
                ) { isAddingProvider = true }

                addedList(
                    count: person.liveProviders.filter(\.isPharmacy).count,
                    noun: "pharmacy",
                    addLabel: "Add a pharmacy",
                    symbol: "cross.case.fill",
                    rows: person.liveProviders.filter(\.isPharmacy).map(\.name)
                ) { isAddingPharmacy = true }
            }

        case .reminders:
            Toggle("Remind me about doses and appointments", isOn: $remindersOn)
                .font(.body)

        case .family:
            VStack(alignment: .leading, spacing: 14) {
                if auth.isSignedIn {
                    Button {
                        isInviting = true
                    } label: {
                        Label("Invite someone", systemImage: "person.badge.plus")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                } else {
                    // Honest rather than a dead button. Sharing needs an
                    // account and this flow deliberately does not force one.
                    Text("Sharing needs an account. You can sign in later from the Sharing tab; everything works on this phone without one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The add-things steps all look the same: what is already there, and one
    /// button that opens the real editor. Reusing the real editor rather than a
    /// cut-down onboarding copy is what keeps the two from drifting.
    private func addedList(
        count: Int,
        noun: String,
        addLabel: String,
        symbol: String,
        rows: [String],
        onAdd: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Label(row, systemImage: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            Button(action: onAdd) {
                Label(count == 0 ? addLabel : "Add another \(noun)", systemImage: symbol)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private func entryList(
        items: Binding<[String]>,
        draft: Binding<String>,
        placeholder: String,
        empty: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items.wrappedValue, id: \.self) { item in
                HStack {
                    Text(item).font(.body)
                    Spacer()
                    Button {
                        items.wrappedValue.removeAll { $0 == item }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if items.wrappedValue.isEmpty {
                Text(empty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                // Drug and condition names are not dictionary words, and
                // autocorrect turning "Losartan" into "Loosen" on an allergy
                // line is the one typo here that could matter.
                TextField(placeholder, text: draft)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .onSubmit { commit(draft: draft, into: items) }
                Button {
                    commit(draft: draft, into: items)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func commit(draft: Binding<String>, into items: Binding<[String]>) {
        let value = draft.wrappedValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !items.wrappedValue.contains(value) else { return }
        items.wrappedValue.append(value)
        draft.wrappedValue = ""
    }

    // MARK: - Moving through

    private func load() {
        hasBirthDate = person.birthDate != nil
        if let existing = person.birthDate { birthDate = existing }
        allergies = person.allergies
        conditions = person.conditions
        bloodType = person.bloodType
        remindersOn = DoseReminderPreferences.isEnabled(personID: person.id)
    }

    private func advance(saving: Bool) {
        if saving { save(step) }
        if isLast {
            onFinished()
        } else {
            index += 1
        }
    }

    /// Only the steps that hold their answer in local state need saving. The
    /// contact, medication and provider steps wrote through their own editors
    /// when they were dismissed, so skipping past them is a no-op rather than
    /// an undo.
    private func save(_ step: Step) {
        switch step {
        case .birthDate:
            person.birthDate = hasBirthDate ? birthDate : nil
            person.recordLocalChange(in: context)

        case .allergies:
            commit(draft: $newAllergy, into: $allergies)
            person.allergies = allergies
            person.recordLocalChange(in: context)

        case .conditions:
            commit(draft: $newCondition, into: $conditions)
            person.conditions = conditions
            person.bloodType = bloodType
            person.recordLocalChange(in: context)

        case .reminders:
            DoseReminderPreferences.setEnabled(remindersOn, personID: person.id)
            Task {
                if remindersOn, !(await NotificationService.shared.isAuthorized()) {
                    let granted = await NotificationService.shared.requestAuthorization()
                    if !granted {
                        DoseReminderPreferences.setEnabled(false, personID: person.id)
                    }
                }
                await DoseReminderScheduler.refresh(in: context)
            }

        case .contact, .medication, .providers, .family:
            break
        }
    }
}

#Preview {
    OnboardingDetailsFlow(person: SampleData.previewPerson()) {}
        .modelContainer(SampleData.previewContainer())
        .environment(AuthService.shared)
}
