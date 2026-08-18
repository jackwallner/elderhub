import SwiftData
import SwiftUI

struct VitalsView: View {
    let person: Person

    @Environment(\.modelContext) private var context
    @Environment(GroupService.self) private var groups
    @State private var isAddingReading = false
    @State private var pendingDeletion: PendingRecordDeletion?
    @State private var editingReading: VitalReading?
    @State private var selectedKind: VitalKind = .bloodPressure

    private var readings: [VitalReading] {
        person.liveVitals
            .filter { $0.kind == selectedKind }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    var body: some View {
        List {
            Section {
                Picker("Reading", selection: $selectedKind) {
                    ForEach(VitalKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.menu)
            }

            if readings.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No \(selectedKind.label.lowercased()) readings",
                        systemImage: selectedKind.symbol
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section(selectedKind.label) {
                    ForEach(readings) { reading in
                        // Tappable: a transposed 140/90 used to be fixable only
                        // by deleting the reading, which loses the row from a
                        // record whose whole value is that it is longitudinal.
                        Button {
                            editingReading = reading
                        } label: {
                            readingRow(reading)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: requestDeletion)
                }
            }
        }
        .navigationTitle("Vitals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingReading = true
                } label: {
                    Label("Add reading", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingReading) {
            VitalEditorSheet(person: person, kind: selectedKind)
        }
        .sheet(item: $editingReading) { reading in
            VitalEditorSheet(person: person, kind: reading.kind, reading: reading)
        }
        .recordDeletionConfirmation($pendingDeletion)
    }

    private func readingRow(_ reading: VitalReading) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(reading.displayValue) \(reading.kind.unit)")
                    .font(.title3.weight(.medium))
                if !reading.note.isEmpty {
                    Text(reading.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(reading.recordedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func requestDeletion(at offsets: IndexSet) {
        let doomed = offsets.compactMap { readings.indices.contains($0) ? readings[$0] : nil }
        guard !doomed.isEmpty else { return }
        let detail = doomed.count == 1
            ? "The \(doomed[0].displayValue) reading from \(doomed[0].recordedAt.formatted(date: .abbreviated, time: .omitted)) leaves the record."
            : "\(doomed.count) readings leave the record."
        pendingDeletion = PendingRecordDeletion(
            title: doomed.count == 1 ? "Delete this reading?" : "Delete \(doomed.count) readings?",
            // A vitals list is only worth anything as a series, so the message
            // says what a gap in it costs rather than just naming the row.
            message: PendingRecordDeletion.message(
                detail + " Readings either side stay, with a gap where this one was.",
                isShared: groups.activeGroupID != nil
            ),
            confirmLabel: "Delete",
            perform: {
                for reading in doomed { reading.tombstone(in: context) }
            }
        )
    }
}

struct VitalEditorSheet: View {
    let person: Person
    @State var kind: VitalKind
    /// Nil to add a reading, an existing row to correct one.
    var reading: VitalReading?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var primary = ""
    @State private var secondary = ""
    @State private var note = ""
    @State private var recordedAt = Date()
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Reading", selection: $kind) {
                    ForEach(VitalKind.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                Section {
                    HStack {
                        TextField(kind.isPaired ? "Systolic" : kind.label, text: $primary)
                            .keyboardType(.decimalPad)
                        if kind.isPaired {
                            Text("/")
                                .foregroundStyle(.secondary)
                            TextField("Diastolic", text: $secondary)
                                .keyboardType(.decimalPad)
                        }
                        Text(kind.unit)
                            .foregroundStyle(.secondary)
                    }

                    DatePicker("When", selection: $recordedAt)
                    TextField("Note", text: $note)
                }
            }
            .navigationTitle(reading == nil ? "Add Reading" : "Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var isValid: Bool {
        guard Double(primary) != nil else { return false }
        if kind.isPaired { return Double(secondary) != nil }
        return true
    }

    private func load() {
        guard !didLoad, let reading else { return }
        didLoad = true
        kind = reading.kind
        primary = Self.text(reading.primaryValue)
        secondary = reading.secondaryValue.map(Self.text) ?? ""
        note = reading.note
        // Kept as the time of the reading, not the time of the correction. A
        // blood pressure taken on Tuesday stays on Tuesday when the typo in it
        // is fixed on Thursday.
        recordedAt = reading.recordedAt
    }

    /// Whole numbers without a trailing ".0", so editing 140/90 does not show
    /// "140.0" back to someone who typed "140".
    private static func text(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    private func save() {
        guard let primaryValue = Double(primary) else { return }
        let target = reading ?? {
            let new = VitalReading(kind: kind, primaryValue: primaryValue, person: person)
            context.insert(new)
            return new
        }()

        target.kind = kind
        target.primaryValue = primaryValue
        target.secondaryValue = kind.isPaired ? Double(secondary) : nil
        target.recordedAt = recordedAt
        target.note = note.trimmingCharacters(in: .whitespaces)
        target.recordLocalChange(in: context)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        VitalsView(person: SampleData.previewPerson())
    }
    .modelContainer(SampleData.previewContainer())
}
