import SwiftData
import SwiftUI

/// Appointments, forwards and backwards.
///
/// This screen used to be a write-up log and nothing else: date-only, sorted
/// newest first, headed "Log what the doctor said while it's fresh". A family
/// looking after a parent spends at least as much of its attention on the
/// appointment that has not happened yet, and there was nowhere to put one.
/// A visit dated later than now is that appointment; see `Visit.isUpcoming`.
struct VisitsView: View {
    let person: Person

    @Environment(\.modelContext) private var context
    @Environment(GroupService.self) private var groups
    @State private var newVisitDate: NewVisitDate?
    @State private var pendingDeletion: PendingRecordDeletion?
    @State private var editingVisit: Visit?

    private var upcoming: [Visit] { person.upcomingVisits() }
    private var past: [Visit] { person.pastVisits() }

    var body: some View {
        List {
            if upcoming.isEmpty, past.isEmpty {
                ContentUnavailableView(
                    "Nothing booked or logged",
                    systemImage: "calendar",
                    description: Text("Add what's coming up, and write down what the doctor said while it's fresh.")
                )
                .listRowBackground(Color.clear)
            } else {
                if !upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcoming) { visit in
                            row(visit)
                        }
                        .onDelete { requestDeletion(of: upcoming, at: $0) }
                    }
                }

                // Headed "Past" only when there is an Upcoming section to tell
                // it apart from. A lone "Past" header over every row the screen
                // has ever held labels a distinction that is not being drawn.
                if !past.isEmpty {
                    if upcoming.isEmpty {
                        Section { pastRows }
                    } else {
                        Section("Past") { pastRows }
                    }
                }
            }
        }
        .navigationTitle("Appointments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // A menu rather than a plain plus, because "you can put next
                // month's cardiology appointment in here" is not something a
                // list of past visits ever says out loud.
                Menu {
                    Button {
                        newVisitDate = NewVisitDate(value: Self.defaultAppointmentDate())
                    } label: {
                        Label("Add an appointment", systemImage: "calendar.badge.plus")
                    }
                    Button {
                        newVisitDate = NewVisitDate(value: Date())
                    } label: {
                        Label("Log a past visit", systemImage: "square.and.pencil")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .accessibilityIdentifier("visits.add")
            }
        }
        .sheet(item: $newVisitDate) { date in
            VisitEditorSheet(person: person, initialDate: date.value)
        }
        .sheet(item: $editingVisit) { visit in
            VisitEditorSheet(person: person, visit: visit)
        }
        .recordDeletionConfirmation($pendingDeletion)
    }

    @ViewBuilder
    private var pastRows: some View {
        ForEach(past) { visit in
            row(visit)
        }
        .onDelete { requestDeletion(of: past, at: $0) }
    }

    /// A visit is usually written up from memory after the appointment, which
    /// is exactly the kind of record that needs correcting later.
    private func row(_ visit: Visit) -> some View {
        Button {
            editingVisit = visit
        } label: {
            VisitRow(visit: visit)
        }
        .buttonStyle(.plain)
    }

    /// Tomorrow morning: a date somebody is more likely to be adjusting than
    /// correcting, unlike "now", which reads as a visit that just happened.
    private static func defaultAppointmentDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private func requestDeletion(of list: [Visit], at offsets: IndexSet) {
        let doomed = offsets.compactMap { list.indices.contains($0) ? list[$0] : nil }
        guard !doomed.isEmpty else { return }
        let noun = doomed.allSatisfy { $0.isUpcoming() } ? "appointment" : "visit"
        let name = doomed.count == 1
            ? (doomed[0].resolvedProviderName.isEmpty ? "this \(noun)" : "the \(noun) with \(doomed[0].resolvedProviderName)")
            : "\(doomed.count) \(noun)s"
        pendingDeletion = PendingRecordDeletion(
            title: doomed.count == 1 ? "Delete this \(noun)?" : "Delete \(doomed.count) \(noun)s?",
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

/// `sheet(item:)` needs an identity, and a bare `Date` has none.
private struct NewVisitDate: Identifiable {
    let value: Date
    var id: TimeInterval { value.timeIntervalSince1970 }
}

private struct VisitRow: View {
    let visit: Visit

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(visit.displayTitle())
                    .font(.body.weight(.medium))
                Spacer()
                Text(visit.dateLabel())
                    .font(.subheadline)
                    .foregroundStyle(visit.isUpcoming() ? .primary : .secondary)
            }

            // Skipped when it is already the title: a row reading "Cardiology
            // review" twice reads as a bug.
            if !visit.reason.isEmpty, visit.reason != visit.displayTitle() {
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
    /// What a new row starts at: now for a write-up, tomorrow morning for an
    /// appointment. Ignored when correcting an existing row.
    var initialDate: Date = Date()

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var provider = ""
    @State private var providerID: UUID?
    @State private var specialty = ""
    @State private var reason = ""
    @State private var notes = ""
    @State private var followUp = ""
    /// True for a row that already carried a time of day. Kept so that editing
    /// an appointment the morning after it happened does not quietly round its
    /// 9:30 down to midnight.
    @State private var loadedWithTime = false
    @State private var didLoad = false

    private var isUpcoming: Bool { date > Date() }

    /// A time picker earns its place on something still to come. On a visit
    /// written up from memory a fortnight later it invites a precision nobody
    /// has, and the row would then print it.
    private var showsTime: Bool { isUpcoming || loadedWithTime }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Date",
                        selection: $date,
                        displayedComponents: showsTime ? [.date, .hourAndMinute] : [.date]
                    )
                    TextField("Provider", text: $provider)
                    TextField("Specialty", text: $specialty)
                    ProviderPickerField(
                        title: "Linked provider", person: person,
                        isPharmacy: false, selection: $providerID
                    )
                } footer: {
                    if isUpcoming {
                        Text("Dated ahead, so it sits under Upcoming and on Today in the week before it.")
                    }
                }

                Section("What it was for") {
                    TextField("Reason for visit", text: $reason)
                }

                // The same field, asked for in the tense the date implies:
                // before the appointment it holds the questions, after it holds
                // the answers.
                Section(isUpcoming ? "What to ask" : "What they said") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(4...10)
                }

                if !isUpcoming || !followUp.isEmpty {
                    Section("Follow up") {
                        TextField("Next step", text: $followUp)
                    }
                }
            }
            .navigationTitle(title)
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

    private var title: String {
        if visit == nil {
            return isUpcoming ? "New Appointment" : "Log Visit"
        }
        return isUpcoming ? "Appointment" : "Visit"
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
        guard !didLoad else { return }
        didLoad = true
        guard let visit else {
            date = initialDate
            loadedWithTime = false
            return
        }
        date = visit.date
        loadedWithTime = visit.hasTimeOfDay()
        // `hasTimeOfDay` is already false for anything in the past, so opening
        // a legacy visit and saving it zeroes the clock it never chose.
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

        // Midnight unless a time was actually chosen, so `hasTimeOfDay` stays
        // the honest answer to "was a time recorded" everywhere it is read.
        target.date = showsTime ? date : Calendar.current.startOfDay(for: date)
        target.provider = provider.trimmingCharacters(in: .whitespaces)
        target.specialty = specialty.trimmingCharacters(in: .whitespaces)
        target.reason = reason.trimmingCharacters(in: .whitespaces)
        target.notes = notes.trimmingCharacters(in: .whitespaces)
        target.followUp = followUp.trimmingCharacters(in: .whitespaces)
        target.providerID = providerID
        target.recordLocalChange(in: context)
        Task { await DoseReminderScheduler.refresh(in: context) }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        VisitsView(person: SampleData.previewPerson())
    }
    .modelContainer(SampleData.previewContainer())
}
