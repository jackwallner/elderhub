import SwiftData
import SwiftUI

struct MedicationEditorSheet: View {
    let person: Person
    /// Nil to add, an existing row to correct one.
    ///
    /// Correction has to be in place rather than delete-and-recreate. A
    /// medication carries its dose history, its refill count and its links to a
    /// prescriber and a pharmacy; recreating it to fix a typo in the strength
    /// throws all of that away, and on a shared record it also tombstones a row
    /// the rest of the family is looking at.
    var medication: Medication?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var strength = ""
    @State private var form: MedicationForm = .tablet
    @State private var purpose = ""
    @State private var prescriber = ""
    @State private var instructions = ""
    @State private var providerID: UUID?
    @State private var pharmacyID: UUID?
    @State private var isAsNeeded = false
    @State private var times: [Date] = [defaultTime()]
    @State private var trackRefills = false
    @State private var quantityRemaining: Double = 30
    @State private var unitsPerDose: Double = 1
    @State private var refillThresholdDays: Int = 7
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Drug names are not dictionary words. Left on, autocorrect
                    // rewrites "Lisinopril" into whatever it thinks you meant, and
                    // a wrong name on this list is the one error that actually matters.
                    TextField("Medication name", text: $name)
                        .font(.title3)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                    TextField("Strength (10 mg)", text: $strength)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Picker("Form", selection: $form) {
                        ForEach(MedicationForm.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }

                Section {
                    Toggle("As needed", isOn: $isAsNeeded)

                    if !isAsNeeded {
                        ForEach(times.indices, id: \.self) { index in
                            DatePicker(
                                "Time \(index + 1)",
                                selection: Binding(
                                    get: { times[index] },
                                    set: { times[index] = $0 }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                        }
                        .onDelete { times.remove(atOffsets: $0) }

                        Button {
                            times.append(Self.defaultTime())
                        } label: {
                            Label("Add a time", systemImage: "plus")
                        }
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    // Two 8:00 AM rows used to save as two 8:00 AM doses, so
                    // Today read "0 of 2" for one tablet and a caregiver could
                    // tick it twice. Saving folds them together; saying so
                    // first is better than silently changing what was typed.
                    if hasDuplicateTimes {
                        Text("Two of these times are the same. They will be saved as one dose.")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Refills") {
                    Toggle("Track refills", isOn: $trackRefills.animation())

                    if trackRefills {
                        HStack {
                            Text("On hand")
                            Spacer()
                            TextField("Quantity", value: $quantityRemaining, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("Units per dose")
                            Spacer()
                            TextField("Units", value: $unitsPerDose, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        Stepper(
                            "Warn at \(refillThresholdDays) day\(refillThresholdDays == 1 ? "" : "s") left",
                            value: $refillThresholdDays, in: 1...30
                        )
                    }
                }

                Section("For the doctor") {
                    // Reads mid-sentence on the emergency card ("for blood pressure"),
                    // so a leading capital looks wrong there.
                    TextField("What it's for", text: $purpose)
                        .textInputAutocapitalization(.never)
                    TextField("Prescriber", text: $prescriber)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                    TextField("Instructions (take with food)", text: $instructions, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    ProviderPickerField(
                        title: "Linked prescriber", person: person,
                        isPharmacy: false, selection: $providerID
                    )
                    ProviderPickerField(
                        title: "Pharmacy", person: person,
                        isPharmacy: true, selection: $pharmacyID
                    )
                } footer: {
                    Text("Link a saved provider so its phone number prints on the medication list.")
                }
            }
            .navigationTitle(medication == nil ? "Add Medication" : "Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("medication-editor.save")
                }
            }
            .onAppear(perform: load)
        }
    }

    private var scheduleMinutes: [Int] {
        Set(times.map { ScheduleEngine.minutes(from: $0) }).sorted()
    }

    private var hasDuplicateTimes: Bool {
        !isAsNeeded && scheduleMinutes.count != times.count
    }

    /// Only once. A sheet's `onAppear` runs again when the app returns from the
    /// background, and reloading there would throw away everything typed since.
    private func load() {
        guard !didLoad, let medication else { return }
        didLoad = true
        name = medication.name
        strength = medication.strength
        form = medication.form
        purpose = medication.purpose
        prescriber = medication.prescriber
        instructions = medication.instructions
        providerID = medication.providerID
        pharmacyID = medication.pharmacyID
        isAsNeeded = medication.isAsNeeded
        if !medication.scheduleMinutes.isEmpty {
            times = medication.scheduleMinutes.sorted().map(Self.time(fromMinutes:))
        }
        // Read from the flag, not from the count. Deriving it from
        // `quantityRemaining > 0` meant a bottle that had just run out loaded
        // with the toggle off, so the user's next save silently discarded the
        // tracking they had set up.
        trackRefills = medication.tracksRefills
        quantityRemaining = max(0, medication.quantityRemaining)
        unitsPerDose = medication.unitsPerDose
        refillThresholdDays = medication.refillThresholdDays
    }

    private func save() {
        let target = medication ?? {
            let new = Medication(name: "", person: person)
            context.insert(new)
            return new
        }()

        target.name = name.trimmingCharacters(in: .whitespaces)
        target.strength = strength.trimmingCharacters(in: .whitespaces)
        target.form = form
        target.purpose = purpose.trimmingCharacters(in: .whitespaces)
        target.prescriber = prescriber.trimmingCharacters(in: .whitespaces)
        target.providerID = providerID
        target.pharmacyID = pharmacyID
        target.instructions = instructions.trimmingCharacters(in: .whitespaces)
        target.isAsNeeded = isAsNeeded
        // Deduplicated: two identical times are one dose, not two, and a
        // schedule that says otherwise makes Today lie about what is left.
        target.scheduleMinutes = isAsNeeded ? [] : scheduleMinutes

        target.tracksRefills = trackRefills
        if trackRefills {
            target.quantityRemaining = max(0, quantityRemaining)
            target.unitsPerDose = unitsPerDose
            target.refillThresholdDays = refillThresholdDays
            // Only a new refill resets the fill date. Correcting the strength
            // of a bottle opened a fortnight ago must not claim it is new.
            if target.lastFilledAt == nil { target.lastFilledAt = Date() }
        } else {
            target.quantityRemaining = 0
        }

        target.recordLocalChange(in: context)
        Task { await DoseReminderScheduler.refresh(in: context) }
        dismiss()
    }

    private static func defaultTime() -> Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private static func time(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
        ) ?? Date()
    }
}

#Preview {
    MedicationEditorSheet(person: SampleData.previewPerson())
        .modelContainer(SampleData.previewContainer())
}
