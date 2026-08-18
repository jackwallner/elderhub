import SwiftData
import SwiftUI

/// What the family pays on one person's behalf.
///
/// This screen exists because the alternative was a note, and a note cannot
/// answer "what is due" or "did anyone pay it". Those two questions are the
/// whole feature; everything here is in service of answering them in a glance.
///
/// Two boundaries it holds, both of which are the reason to read `Bill`'s doc
/// comment before adding a field here: nothing on this screen is a credential,
/// and nothing on this screen pays anything. Marking a bill paid records that a
/// human says they paid it, exactly as ticking a dose records that a human says
/// a tablet was swallowed (I6).
struct BillsView: View {
    let person: Person

    @Environment(\.modelContext) private var context
    @Environment(GroupService.self) private var groups

    @State private var isAddingBill = false
    @State private var editingBill: Bill?
    @State private var pendingDeletion: PendingRecordDeletion?

    private var bills: [Bill] { person.liveBills }
    private var sections: [(bucket: BillBucket, bills: [Bill])] { BillPlanner.sections(bills) }
    private var recentlyPaid: [Bill] { BillPlanner.recentlyPaid(bills) }

    var body: some View {
        List {
            if bills.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No bills yet", systemImage: "dollarsign.circle")
                    } description: {
                        Text("Keep track of what the family pays for \(person.displayLabel): the care home, the utilities, an insurance premium. Elderhub records what is due and who paid it. It never pays anything itself.")
                    } actions: {
                        Button("Add a bill") { isAddingBill = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                if outstandingTotal > 0 {
                    Section {
                        LabeledContent("Still to pay") {
                            Text(outstandingLabel)
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                        }
                    } footer: {
                        // Said plainly, because a total is the number people
                        // read fastest and trust most, and this one is only as
                        // good as what somebody typed in.
                        Text("Adds up every open bill here, including the ones on autopay. It is only what the family has entered.")
                    }
                }

                ForEach(sections, id: \.bucket) { section in
                    Section(section.bucket.label) {
                        ForEach(section.bills) { bill in
                            billRow(bill, isPaidSection: false)
                        }
                        .onDelete { offsets in
                            requestDeletion(section.bills, at: offsets)
                        }
                    }
                }

                if !recentlyPaid.isEmpty {
                    Section {
                        ForEach(recentlyPaid) { bill in
                            billRow(bill, isPaidSection: true)
                        }
                        .onDelete { offsets in
                            requestDeletion(recentlyPaid, at: offsets)
                        }
                    } header: {
                        Text("Paid recently")
                    } footer: {
                        Text("The last two months. A paid bill is kept so the family can answer \"did anyone pay the March invoice\".")
                    }
                }
            }
        }
        .navigationTitle("Bills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingBill = true
                } label: {
                    Label("Add bill", systemImage: "plus")
                }
                .accessibilityIdentifier("bills.add")
            }
        }
        .sheet(isPresented: $isAddingBill) {
            BillEditorSheet(person: person, bill: nil)
        }
        .sheet(item: $editingBill) { bill in
            BillEditorSheet(person: person, bill: bill)
        }
        .recordDeletionConfirmation($pendingDeletion)
    }

    // MARK: - Rows

    private func billRow(_ bill: Bill, isPaidSection: Bool) -> some View {
        Button {
            editingBill = bill
        } label: {
            BillRow(bill: bill)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            if bill.isPaid {
                Button {
                    bill.markUnpaid(in: context)
                } label: {
                    Label("Not paid", systemImage: "arrow.uturn.backward")
                }
                .tint(.orange)
            } else {
                Button {
                    bill.markPaid(by: CareTaskAuthor.name(from: groups), in: context)
                } label: {
                    Label("Paid", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
        .accessibilityIdentifier("bills.row.\(bill.id.uuidString)")
    }

    // MARK: - Totals

    private var outstandingTotal: Double { BillPlanner.outstandingTotal(bills) }

    private var outstandingLabel: String {
        outstandingTotal.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    // MARK: - Deleting

    private func requestDeletion(_ list: [Bill], at offsets: IndexSet) {
        let doomed = offsets.compactMap { list.indices.contains($0) ? list[$0] : nil }
        guard !doomed.isEmpty else { return }
        pendingDeletion = PendingRecordDeletion(
            title: doomed.count == 1 ? "Delete \(doomed[0].payee)?" : "Delete \(doomed.count) bills?",
            message: PendingRecordDeletion.message(
                doomed.count == 1
                    ? "The record of what was owed, and of who paid it, goes with it."
                    : "The record of what was owed, and of who paid it, goes with them.",
                isShared: groups.activeGroupID != nil
            ),
            confirmLabel: "Delete",
            perform: {
                for bill in doomed { bill.tombstone(in: context) }
            }
        )
    }
}

// MARK: - Row

private struct BillRow: View {
    let bill: Bill

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(bill.payee.isEmpty ? "Untitled bill" : bill.payee)
                    .font(.body.weight(.medium))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(bill.amountLabel)
                .font(.body.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(bill.isPaid ? .secondary : .primary)
        }
        .padding(.vertical, 4)
    }

    /// Every clause here is a fact about the row, in the order someone scanning
    /// the list needs it: when, how often, who paid.
    private var subtitle: String {
        var parts: [String] = []

        if let paidAt = bill.paidAt {
            // Who and when, and nothing else. A paid row that also carried the
            // recurrence wrapped onto a second line for a fact the reader of a
            // "Paid recently" section is not looking for.
            var paid = "Paid \(paidAt.formatted(date: .abbreviated, time: .omitted))"
            if !bill.paidByName.isEmpty { paid += " by \(bill.paidByName)" }
            return paid
        }

        if let dueAt = bill.dueAt {
            let calendar = Calendar.current
            if calendar.startOfDay(for: dueAt) < calendar.startOfDay(for: Date()) {
                parts.append("Was due \(dueAt.formatted(date: .abbreviated, time: .omitted))")
            } else if calendar.isDateInToday(dueAt) {
                parts.append("Due today")
            } else {
                parts.append("Due \(dueAt.formatted(date: .abbreviated, time: .omitted))")
            }
        }

        // Autopay replaces the recurrence rather than following it: three
        // clauses wrapped the row onto a second line reading only "· autopay",
        // and how often the bank pays it is the least useful of the three.
        if bill.isAutoPay {
            parts.append("autopay")
        } else if bill.recurrence != .never {
            parts.append(bill.recurrence.shortLabel)
        }

        return parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        BillsView(person: SampleData.previewPerson())
    }
    .modelContainer(SampleData.previewContainer())
    .environment(GroupService.shared)
}
