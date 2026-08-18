import SwiftData
import SwiftUI

/// One person's merged chronological history (plan82 slice E): doses that
/// weren't taken, visits, vitals, incidents, check-ins, and medication
/// started/stopped markers.
///
/// I1: everything here comes from the local SwiftData store. `loadWindow`
/// only ever calls `context.fetch`; there is no sync call on appear, no
/// spinner, and no empty state that blames the network.
struct TimelineView: View {
    let person: Person

    @Environment(\.modelContext) private var context

    @State private var selectedKind: TimelineEntryKind?
    @State private var windowMonths = 3
    @State private var doseLogs: [DoseLog] = []
    @State private var checkIns: [CheckInRecord] = []
    @State private var reachedWindowLimit = false

    /// Two years of a busy person is thousands of dose logs and daily
    /// check-ins, so those two are fetched through a widening date window
    /// instead of loaded in full. The person's live visits, vitals and
    /// care events stay small enough in practice to use as-is.
    private static let maxWindowMonths = 24

    private var entries: [TimelineEntry] {
        TimelineBuilder.build(
            personID: person.id,
            visits: person.liveVisits,
            vitals: person.liveVitals,
            careEvents: person.liveCareEvents,
            tasks: person.liveTasks,
            checkIns: checkIns,
            medications: person.liveMedications,
            doseLogs: doseLogs
        )
    }

    private var filteredEntries: [TimelineEntry] {
        guard let selectedKind else { return entries }
        return entries.filter { $0.kind == selectedKind }
    }

    private var groupedByMonth: [(month: Date, entries: [TimelineEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            calendar.date(from: calendar.dateComponents([.year, .month], from: entry.date)) ?? entry.date
        }
        return grouped.keys.sorted(by: >).map { month in
            (month: month, entries: grouped[month]!.sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $selectedKind) {
                    Text("All").tag(TimelineEntryKind?.none)
                    ForEach(TimelineEntryKind.allCases) { kind in
                        Text(kind.label).tag(TimelineEntryKind?.some(kind))
                    }
                }
                .pickerStyle(.menu)
            }

            if filteredEntries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "clock",
                        description: Text("Visits, vitals, incidents and missed doses for \(person.displayLabel) will show up here.")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(groupedByMonth, id: \.month) { group in
                    Section(group.month.formatted(.dateTime.month(.wide).year())) {
                        ForEach(group.entries) { entry in
                            TimelineRow(entry: entry)
                        }
                    }
                }

                if !reachedWindowLimit {
                    Section {
                        Button("Load earlier history", action: extendWindow)
                    }
                }
            }
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadWindow)
    }

    private func loadWindow() {
        guard let windowStart = Calendar.current.date(byAdding: .month, value: -windowMonths, to: Date()) else { return }

        let takenRaw = DoseStatus.taken.rawValue
        var doseDescriptor = FetchDescriptor<DoseLog>(
            predicate: #Predicate<DoseLog> {
                $0.scheduledAt >= windowStart && $0.deletedAt == nil && $0.statusRaw != takenRaw
            }
        )
        doseDescriptor.sortBy = [SortDescriptor(\.scheduledAt, order: .reverse)]
        let medicationIDs = Set(person.liveMedications.map(\.id))
        let fetchedDoses = (try? context.fetch(doseDescriptor)) ?? []
        // Filtered by medication ownership after the fetch: `DoseLog` has no
        // stored link to a person, only to a medication, and chaining an
        // optional-to-optional relationship inside a #Predicate is unreliable.
        doseLogs = fetchedDoses.filter { log in
            guard let medicationID = log.medication?.id else { return false }
            return medicationIDs.contains(medicationID)
        }

        let personID = person.id
        var checkInDescriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate<CheckInRecord> {
                $0.personID == personID && $0.pressedAt >= windowStart
            }
        )
        checkInDescriptor.sortBy = [SortDescriptor(\.pressedAt, order: .reverse)]
        checkIns = (try? context.fetch(checkInDescriptor)) ?? []
    }

    private func extendWindow() {
        guard !reachedWindowLimit else { return }
        windowMonths += 6
        loadWindow()
        if windowMonths >= Self.maxWindowMonths {
            reachedWindowLimit = true
        }
    }
}

private struct TimelineRow: View {
    let entry: TimelineEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.body.weight(.medium))
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var metaLine: String {
        let dateText = entry.date.formatted(date: .abbreviated, time: .shortened)
        return entry.recordedBy.isEmpty ? dateText : "\(dateText) · \(entry.recordedBy)"
    }
}

#Preview {
    NavigationStack {
        TimelineView(person: SampleData.previewPerson())
    }
    .modelContainer(SampleData.previewContainer())
}
