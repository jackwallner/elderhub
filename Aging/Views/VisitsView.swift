import SwiftData
import SwiftUI

struct VisitsView: View {
    let person: Person

    @Environment(\.modelContext) private var context
    @Environment(GroupService.self) private var groups
    @State private var isAddingVisit = false
    @State private var pendingDeletion: PendingRecordDeletion?
    @State private var editingVisit: Visit?

    private var visits: [Visit] {
        person.liveVisits.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            if visits.isEmpty {
                ContentUnavailableView(
                    "No visits logged",
                    systemImage: "stethoscope",
                    description: Text("Log what the doctor said while it's fresh.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(visits) { visit in
                    // A visit is usually written up from memory after the
                    // appointment, which is exactly the kind of record that
                    // needs correcting later.
                    Button {
                        editingVisit = visit
                    } label: {
                        VisitRow(visit: visit)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: requestDeletion)
            }
        }
        .navigationTitle("Visits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingVisit = true
                } label: {
                    Label("Log visit", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingVisit) {
            VisitEditorSheet(person: person)
        }
        .sheet(item: $editingVisit) { visit in
            VisitEditorSheet(person: person, visit: visit)
        }
        .recordDeletionConfirmation($pendingDeletion)
    }

    private func requestDeletion(at offsets: IndexSet) {
        let doomed = offsets.compactMap { visits.indices.contains($0) ? visits[$0] : nil }
        guard !doomed.isEmpty else { return }
        let name = doomed.count == 1
            ? (doomed[0].resolvedProviderName.isEmpty ? "this visit" : "the visit with \(doomed[0].resolvedProviderName)")
            : "\(doomed.count) visits"
        pendingDeletion = PendingRecordDeletion(
            title: doomed.count == 1 ? "Delete this visit?" : "Delete \(doomed.count) visits?",
            message: PendingRecordDeletion.message(
                "Whatever was written up about \(name) goes with it.",
                isShared: groups.activeGroupID != nil
            ),
            confirmLabel: "Delete",
            perform: {
                for visit in doomed { visit.tombstone(in: context) }
            }
        )
    }
}

private struct VisitRow: View {
    let visit: Visit

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(visit.resolvedProviderName.isEmpty ? "Visit" : visit.resolvedProviderName)
                    .font(.body.weight(.medium))
                Spacer()
                Text(visit.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !visit.reason.isEmpty {
                Text(visit.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !visit.notes.isEmpty {
                Text(visit.notes)
                    .font(.subheadline)
                    .lineLimit(3)
            }

            if !visit.followUp.isEmpty {
                Label(visit.followUp, systemImage: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 3)
    }
}

struct VisitEditorSheet: View {
    let person: Person
    /// Nil to log a new visit, an existing row to correct one.
    var visit: Visit?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var provider = ""
    @State private var providerID: UUID?
    @State private var specialty = ""
    @State private var reason = ""
    @State private var notes = ""
    @State private var followUp = ""
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Provider", text: $provider)
                    TextField("Specialty", text: $specialty)
                    ProviderPickerField(
                        title: "Linked provider", person: person,
                        isPharmacy: false, selection: $providerID
                    )
                }

                Section("What it was for") {
                    TextField("Reason for visit", text: $reason)
                }

                Section("What they said") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(4...10)
                }

                Section("Follow up") {
                    TextField("Next step", text: $followUp)
                }
            }
            .navigationTitle(visit == nil ? "Log Visit" : "Visit")
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
            .onAppear(perform: load)
        }
    }

    /// A date on its own is not a visit. Saving one produced a row reading
    /// "Visit, 4 Aug" in the list and in the Timeline, which nobody can
    /// interpret later and which cannot be told apart from a real appointment
    /// somebody forgot to write up.
    private var hasContent: Bool {
        ![provider, specialty, reason, notes, followUp]
            .allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || providerID != nil
    }

    private func load() {
        guard !didLoad, let visit else { return }
        didLoad = true
        date = visit.date
        provider = visit.provider
        providerID = visit.providerID
        specialty = visit.specialty
        reason = visit.reason
        notes = visit.notes
        followUp = visit.followUp
    }

    private func save() {
        let target = visit ?? {
            let new = Visit(date: date, person: person)
            context.insert(new)
            return new
        }()

        target.date = date
        target.provider = provider.trimmingCharacters(in: .whitespaces)
        target.specialty = specialty.trimmingCharacters(in: .whitespaces)
        target.reason = reason.trimmingCharacters(in: .whitespaces)
        target.notes = notes.trimmingCharacters(in: .whitespaces)
        target.followUp = followUp.trimmingCharacters(in: .whitespaces)
        target.providerID = providerID
        target.recordLocalChange(in: context)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        VisitsView(person: SampleData.previewPerson())
    }
    .modelContainer(SampleData.previewContainer())
}
