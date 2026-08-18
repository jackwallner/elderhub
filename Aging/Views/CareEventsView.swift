import SwiftData
import SwiftUI

/// The incident and symptom log reachable from `PersonDetailView` (plan82
/// slice D). One typed note per fall, ER visit, hospital stay, symptom, mood,
/// appetite, sleep or pain entry.
///
/// I6: this screen only ever shows what a human typed after the fact. No
/// chart, no trend language, no "3 falls this month suggests..." — count and
/// list, nothing inferential.
struct CareEventsView: View {
    let person: Person

    @Environment(\.modelContext) private var context
    @Environment(GroupService.self) private var groups
    @State private var isAddingEvent = false
    @State private var pendingDeletion: PendingRecordDeletion?
    @State private var editingEvent: CareEvent?
    @State private var filterKind: CareEventKind?

    private var filteredEvents: [CareEvent] {
        let all = person.liveCareEvents
        guard let filterKind else { return all }
        return all.filter { $0.kind == filterKind }
    }

    private var monthGroups: [(month: Date, events: [CareEvent])] {
        CareEvent.groupedByMonth(filteredEvents)
    }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filterKind) {
                    Text("All").tag(nil as CareEventKind?)
                    ForEach(CareEventKind.allCases) { kind in
                        Text(kind.label).tag(kind as CareEventKind?)
                    }
                }
                .pickerStyle(.menu)
            }

            if filteredEvents.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No entries yet",
                        systemImage: "note.text",
                        description: Text("Log a fall, symptom or anything else worth remembering.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(monthGroups, id: \.month) { group in
                    Section(monthLabel(group.month)) {
                        ForEach(group.events) { event in
                            Button {
                                editingEvent = event
                            } label: {
                                CareEventRow(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in requestDeletion(group.events, at: offsets) }
                    }
                }
            }
        }
        .navigationTitle("Incidents & Symptoms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingEvent = true
                } label: {
                    Label("Add entry", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingEvent) {
            CareEventEditorSheet(person: person, event: nil)
        }
        .sheet(item: $editingEvent) { event in
            CareEventEditorSheet(person: person, event: event)
        }
        .recordDeletionConfirmation($pendingDeletion)
    }

    private func monthLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    /// Tombstones rather than hard-deletes: a row that only disappears
    /// locally would never be pushed, so the delete would never leave this
    /// phone.
    private func requestDeletion(_ events: [CareEvent], at offsets: IndexSet) {
        let doomed = offsets.compactMap { events.indices.contains($0) ? events[$0] : nil }
        guard !doomed.isEmpty else { return }
        pendingDeletion = PendingRecordDeletion(
            title: doomed.count == 1 ? "Delete this entry?" : "Delete \(doomed.count) entries?",
            // A fall or a bad day is the kind of thing a doctor asks about
            // months later, which is the whole reason it was logged.
            message: PendingRecordDeletion.message(
                doomed.count == 1
                    ? "It leaves the timeline, so it will not be there to look back on."
                    : "They leave the timeline, so they will not be there to look back on.",
                isShared: groups.activeGroupID != nil
            ),
            confirmLabel: "Delete",
            perform: {
                for event in doomed { event.tombstone(in: context) }
            }
        )
    }
}

private struct CareEventRow: View {
    let event: CareEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(event.kind.label)
                        .font(.body.weight(.medium))
                    if event.severity > 0 {
                        Text("Severity \(event.severity)/10")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !event.note.isEmpty {
                    Text(event.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if !event.recordedBy.isEmpty {
                    Text("Logged by \(event.recordedBy)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

struct CareEventEditorSheet: View {
    let person: Person
    let event: CareEvent?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var kind: CareEventKind = .symptom
    @State private var occurredAt = Date()
    @State private var severity = 0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(CareEventKind.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                Section {
                    DatePicker("When", selection: $occurredAt)
                    Stepper(severityLabel, value: $severity, in: 0...10)
                    TextField("What happened", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        // Two people in a family will not use a bare 0 to 10
                        // the same way, and a symptom log nobody can compare
                        // across entries is not much of a log. Endpoints only:
                        // anything more would be the app grading a symptom,
                        // which it has no business doing (I6).
                        Text("Severity is however it seemed: 1 is barely noticeable, 10 is the worst it has been.")
                        Text("This is a record, not an alert. Nobody is notified automatically.")
                    }
                }
            }
            .navigationTitle(event == nil ? "Add Entry" : "Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!hasContent)
                }
            }
            .onAppear {
                guard let event else { return }
                kind = event.kind
                occurredAt = event.occurredAt
                severity = event.severity
                note = event.note
            }
        }
    }

    private var severityLabel: String {
        severity == 0 ? "Severity not set" : "Severity \(severity)/10"
    }

    /// The type picker always holds a value, so an untouched form used to save
    /// as a Symptom with no severity and nothing written down. That is a row in
    /// the list and a row in the Timeline that says nothing at all.
    ///
    /// A fall, an ER visit or a hospital stay is its own content: the type is
    /// the fact, and a caregiver logging one at speed should not be made to
    /// write a sentence first. Everything else describes a degree of something,
    /// so it needs a severity or a note to mean anything later.
    private var hasContent: Bool {
        switch kind {
        case .fall, .erVisit, .hospitalStay:
            return true
        default:
            return severity > 0 || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func save() {
        let target = event ?? {
            let new = CareEvent(kind: kind, recordedBy: "You", person: person)
            context.insert(new)
            return new
        }()

        target.kind = kind
        target.occurredAt = occurredAt
        target.severity = severity
        target.note = note.trimmingCharacters(in: .whitespaces)
        target.recordLocalChange(in: context)

        dismiss()
    }
}

#Preview {
    NavigationStack {
        CareEventsView(person: SampleData.previewPerson())
    }
    .modelContainer(SampleData.previewContainer())
}
