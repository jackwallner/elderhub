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
    /// Every day until told otherwise, which is what the model's empty
    /// `weekdays` means. Held as all seven rather than as an empty set so the
    /// picker has something to draw and so "none selected" is never a state a
    /// tap can reach.
    @State private var selectedDays: Set<Int> = Set(1...7)
    @State private var trackRefills = false
    @State private var quantityRemaining: Double = 30
    @State private var unitsPerDose: Double = 1
    @State private var refillThresholdDays: Int = 7
    /// Applied on Save like everything else on this sheet, so Cancel means
    /// cancel. Stopping used to have no representation at all: the only way to
    /// clear a medication off the list was to delete it, which took every dose
    /// ever logged against it with it.
    @State private var isStopped = false
    @State private var stoppedOn: Date?
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

                        // Weekly bisphosphonates, methotrexate, the Monday
                        // water tablet: the model, the sync and the reminders
                        // have always carried `weekdays`, and there was no way
                        // to type one in. Every such medication had to be
                        // entered as a daily one, which put it on the list a
                        // nurse reads as a daily one.
                        WeekdayPicker(selection: $selectedDays)
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
                    } else if !isAsNeeded, times.isEmpty {
                        // Deleting the last time used to save a medication that
                        // was neither timed nor as-needed: it appeared on no
                        // day's dose list, printed with no times, and silently
                        // acquired an 8:00 AM the next time the sheet was
                        // opened. It is saved as as-needed instead, and said so
                        // before the tap rather than after.
                        Text("With no times, this is saved as an as-needed medication.")
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

                if medication != nil {
                    Section {
                        // Text only. A `Label` here draws its symbol in the
                        // accent colour beside red text, which reads as two
                        // controls rather than one.
                        if isStopped {
                            Button("Taking this again") { isStopped = false }
                        } else {
                            Button("Stop taking this", role: .destructive) {
                                isStopped = true
                            }
                        }
                    } footer: {
                        if isStopped {
                            Text(stoppedFooter)
                                .foregroundStyle(.orange)
                        } else {
                            Text("Takes it off the dose list and off the emergency card, and keeps every dose already recorded.")
                        }
                    }
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

    private var stoppedFooter: String {
        guard let stoppedOn else {
            return "Saved as stopped. It comes off the dose list and off the emergency card, and its recorded doses stay."
        }
        return "Stopped \(stoppedOn.formatted(date: .abbreviated, time: .omitted)). It is off the dose list and off the emergency card, and its recorded doses stay."
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
        // Empty on the model is every day, which is all seven here.
        let saved = Set(medication.weekdays.filter { (1...7).contains($0) })
        selectedDays = saved.isEmpty ? Set(1...7) : saved
        isStopped = !medication.isActive
        stoppedOn = medication.endDate
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
        // A medication with no times cannot be a scheduled one, whatever the
        // toggle says: see the footer above.
        let savedAsNeeded = isAsNeeded || times.isEmpty
        target.isAsNeeded = savedAsNeeded
        // Deduplicated: two identical times are one dose, not two, and a
        // schedule that says otherwise makes Today lie about what is left.
        target.scheduleMinutes = savedAsNeeded ? [] : scheduleMinutes
        // Empty means every day. Storing all seven would mean the same thing
        // and would print a week's worth of day names on the emergency card.
        target.weekdays = savedAsNeeded || selectedDays.count == 7
            ? []
            : selectedDays.sorted()

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

        // Only on the change itself, so re-saving a medication stopped in June
        // does not re-date it to today.
        if isStopped, target.isActive {
            target.stop()
        } else if !isStopped, !target.isActive {
            target.restart()
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

/// The seven-day repeat control, in the calendar's own week order.
///
/// One day can never be turned off on its own: a schedule with no days is not
/// a schedule, and the model has no way to store one. Tapping the last
/// remaining day does nothing, which is duller than an alert and cannot be got
/// wrong.
private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    private var days: [Int] { ScheduleEngine.orderedWeekdays() }

    private var summary: String {
        let label = ScheduleEngine.weekdayLabel(for: Array(selection))
        return label.isEmpty ? "Every day" : label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Days")
                Spacer()
                Text(summary)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let isOn = selection.contains(day)
                    Button {
                        toggle(day)
                    } label: {
                        Text(narrowSymbol(day))
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(
                                isOn ? Color.accentColor : Color.secondary.opacity(0.15),
                                in: Circle()
                            )
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                    }
                    // Without this every tap in the row activates the row
                    // itself, so the first day tapped is the only one that
                    // ever changes.
                    .buttonStyle(.borderless)
                    .accessibilityLabel(fullSymbol(day))
                    .accessibilityValue(isOn ? "On" : "Off")
                    .accessibilityIdentifier("medication-editor.weekday.\(day)")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func toggle(_ day: Int) {
        if selection.contains(day) {
            guard selection.count > 1 else { return }
            selection.remove(day)
        } else {
            selection.insert(day)
        }
    }

    private func narrowSymbol(_ day: Int) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return symbols.indices.contains(day - 1) ? symbols[day - 1] : ""
    }

    private func fullSymbol(_ day: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols.indices.contains(day - 1) ? symbols[day - 1] : ""
    }
}

#Preview {
    MedicationEditorSheet(person: SampleData.previewPerson())
        .modelContainer(SampleData.previewContainer())
}
