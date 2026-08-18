import SwiftData
import SwiftUI

/// Add or correct one bill.
///
/// The field list is deliberately short and deliberately incomplete: there is
/// no account number, no reference, no login and no card, because a screen
/// called Bills is exactly where a family would put them if the app left a box
/// open for it. The footer says so at the point of entry, which is the only
/// place a boundary like that is any use (the same reasoning as
/// `CareNoteEditorSheet`, and architecture §14).
struct BillEditorSheet: View {
    let person: Person
    let bill: Bill?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(GroupService.self) private var groups

    @State private var payee = ""
    @State private var amount: Double = 0
    @State private var notes = ""
    @State private var category: BillCategory = .other
    @State private var recurrence: BillRecurrence = .monthly
    @State private var hasDueDate = true
    @State private var dueAt = Date()
    @State private var isAutoPay = false
    @State private var isPaid = false

    private var trimmedPayee: String {
        payee.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Who gets paid", text: $payee)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("bill-editor.payee")

                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField(
                            "Amount",
                            value: $amount,
                            format: .currency(code: currencyCode)
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("bill-editor.amount")
                    }

                    Picker("Kind", selection: $category) {
                        ForEach(BillCategory.allCases) { option in
                            Label(option.label, systemImage: option.symbol).tag(option)
                        }
                    }
                }

                Section {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueAt, displayedComponents: [.date])
                        Picker("Repeat", selection: $recurrence) {
                            ForEach(BillRecurrence.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    }
                } footer: {
                    if hasDueDate, recurrence != .never {
                        Text("Marking this paid adds the next one automatically. The paid one stays, so the family can see it was paid.")
                    }
                }

                Section {
                    Toggle("Paid by the bank automatically", isOn: $isAutoPay)
                } footer: {
                    // The reason this toggle exists at all: without it, every
                    // direct debit in the list eventually reads as overdue and
                    // the overdue section stops meaning anything.
                    Text("Autopay bills are listed but never counted as overdue. Elderhub does not pay anything or tell anyone to; it only records what the family has entered.")
                }

                if bill != nil {
                    Section {
                        Toggle("Paid", isOn: $isPaid)
                        if let paidAt = bill?.paidAt, isPaid {
                            LabeledContent("Marked paid") {
                                Text(paidAt.formatted(date: .abbreviated, time: .omitted))
                            }
                            if let paidBy = bill?.paidByName, !paidBy.isEmpty {
                                LabeledContent("By", value: paidBy)
                            }
                        }
                    }
                }

                Section {
                    TextField("What this covers", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityIdentifier("bill-editor.notes")
                } header: {
                    Text("Notes")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Every helper in your care circle can see this. It syncs with the rest of \(person.displayLabel)'s record.")
                        Text("Please don't keep account numbers, card details or logins here. This is an ordinary note, not a secure vault.")
                    }
                }
            }
            .navigationTitle(bill == nil ? "New Bill" : "Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedPayee.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let bill else { return }
        payee = bill.payee
        amount = bill.amount
        notes = bill.notes
        category = bill.category
        recurrence = bill.recurrence
        hasDueDate = bill.dueAt != nil
        dueAt = bill.dueAt ?? Date()
        isAutoPay = bill.isAutoPay
        isPaid = bill.isPaid
    }

    private func save() {
        guard !trimmedPayee.isEmpty else { return }

        let target = bill ?? {
            let new = Bill(
                payee: trimmedPayee,
                createdByName: CareTaskAuthor.name(from: groups),
                person: person
            )
            context.insert(new)
            return new
        }()

        target.payee = trimmedPayee
        target.amount = max(0, amount)
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.category = category
        target.dueAt = hasDueDate ? dueAt : nil
        // A repeat with no due date has nothing to repeat from.
        target.recurrence = hasDueDate ? recurrence : .never
        target.isAutoPay = isAutoPay

        // Toggling paid here goes through the same call the swipe uses, so a
        // recurring bill spawns its next period whichever way it was ticked.
        // Editing an already-paid bill must not re-run it, hence the compare.
        if isPaid != target.isPaid {
            if isPaid {
                target.markPaid(by: CareTaskAuthor.name(from: groups), in: context)
            } else {
                target.markUnpaid(in: context)
            }
        } else {
            target.recordLocalChange(in: context)
        }

        dismiss()
    }
}

#Preview {
    BillEditorSheet(person: SampleData.previewPerson(), bill: nil)
        .modelContainer(SampleData.previewContainer())
        .environment(GroupService.shared)
}
