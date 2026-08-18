import SwiftData
import SwiftUI

/// The family's free-form notes about one person: the screen for everything the
/// other screens have no field for.
///
/// Deliberately the least structured thing in the app. There is a title, a body
/// and a pin, and that is the whole model, because the value here is that a
/// family can write down the gate code and what to ask the neurologist next
/// time without the app having an opinion about any of it.
///
/// The one thing it is not is a password vault (architecture §14). The body is
/// plain text under the group's ordinary permissions and it is searchable, so
/// the editor says so where someone is about to type rather than leaving the
/// boundary to a design document.
///
/// I6: notes are never read back to anyone as an assessment, never summarised,
/// and never surfaced anywhere that implies the app understood them.
struct CareNotesView: View {
    let person: Person

    @Environment(\.modelContext) private var context
    @Environment(GroupService.self) private var groups

    @State private var editingNote: CareNote?
    @State private var isAddingNote = false
    @State private var pendingDeletion: PendingRecordDeletion?

    private var notes: [CareNote] { person.liveNotes }

    var body: some View {
        List {
            if notes.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No notes yet", systemImage: "doc.text")
                    } description: {
                        // The examples deliberately avoid anything credential
                        // -shaped. Suggesting the gate code here and then
                        // warning "not a secure vault" in the editor is the
                        // app arguing with itself at the point of entry.
                        Text("Keep anything here that the other screens have no place for: how she likes her tea, the pharmacy's opening hours, what to ask at the next appointment.")
                    } actions: {
                        Button("Add a note") { isAddingNote = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(notes) { note in
                    Button {
                        editingNote = note
                    } label: {
                        CareNoteRow(note: note)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        Button {
                            togglePin(note)
                        } label: {
                            Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
                        }
                        .tint(.orange)
                    }
                }
                .onDelete(perform: requestDeletion)
            }
        }
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingNote = true
                } label: {
                    Label("Add note", systemImage: "plus")
                }
                .accessibilityIdentifier("notes.add")
            }
        }
        .sheet(isPresented: $isAddingNote) {
            CareNoteEditorSheet(person: person, note: nil)
        }
        .sheet(item: $editingNote) { note in
            CareNoteEditorSheet(person: person, note: note)
        }
        .recordDeletionConfirmation($pendingDeletion)
    }

    private func togglePin(_ note: CareNote) {
        note.isPinned.toggle()
        note.recordLocalChange(in: context)
    }

    /// Tombstones rather than hard-deletes: a row that only disappears locally
    /// would never be pushed, so the delete would never leave this phone.
    private func requestDeletion(at offsets: IndexSet) {
        let current = notes
        let doomed = offsets.compactMap { current.indices.contains($0) ? current[$0] : nil }
        guard !doomed.isEmpty else { return }
        pendingDeletion = PendingRecordDeletion(
            title: doomed.count == 1 ? "Delete \"\(doomed[0].displayTitle)\"?" : "Delete \(doomed.count) notes?",
            message: PendingRecordDeletion.message(
                doomed.count == 1
                    ? "Whatever the note says goes with it."
                    : "Whatever those notes say goes with them.",
                isShared: groups.activeGroupID != nil
            ),
            confirmLabel: "Delete",
            perform: {
                for note in doomed { note.tombstone(in: context) }
            }
        )
    }
}

private struct CareNoteRow: View {
    let note: CareNote

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if note.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(width: 16)
                    .padding(.top, 3)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(note.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                if !note.previewBody.isEmpty {
                    Text(note.previewBody)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        var parts = [note.updatedAt.formatted(date: .abbreviated, time: .omitted)]
        if !note.createdByName.isEmpty { parts.append(note.createdByName) }
        return parts.joined(separator: " · ")
    }
}

struct CareNoteEditorSheet: View {
    let person: Person
    let note: CareNote?

    @Environment(\.modelContext) private var context
    @Environment(GroupService.self) private var groups
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    /// Not `body`: the view's own `body` owns that name.
    @State private var text = ""
    @State private var isPinned = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Note", text: $text, axis: .vertical)
                        .lineLimit(6...20)
                } footer: {
                    // The only guidance on the screen, and it is a boundary
                    // rather than a suggestion. Everyone in the family group
                    // can read this, and it syncs like the rest of the record:
                    // people should know that before they type.
                    //
                    // The second line is the same boundary the provider editor
                    // draws around portal links, and it is needed more here.
                    // This field is plain text under the group's ordinary
                    // permissions, it is returned by search, and it is not a
                    // password vault (architecture §14). Without saying so, an
                    // empty box that invites "anything else" is where a family
                    // will eventually put a banking password.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Every helper in your care circle can see this. It syncs with the rest of \(person.displayLabel)'s record.")
                        Text("Please don't keep passwords or card numbers here. This is an ordinary note, not a secure vault.")
                    }
                }

                Section {
                    Toggle("Pin to the top", isOn: $isPinned)
                }
            }
            .navigationTitle(note == nil ? "New Note" : "Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(isBlank)
                        .accessibilityIdentifier("notes.save")
                }
            }
            .onAppear {
                guard let note else { return }
                title = note.title
                text = note.body
                isPinned = note.isPinned
            }
        }
    }

    private var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let target = note ?? {
            let new = CareNote(createdByName: CareTaskAuthor.name(from: groups), person: person)
            context.insert(new)
            return new
        }()

        target.title = title.trimmingCharacters(in: .whitespaces)
        target.body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        target.isPinned = isPinned
        target.recordLocalChange(in: context)

        dismiss()
    }
}

#Preview {
    NavigationStack {
        CareNotesView(person: SampleData.previewPerson())
    }
    .modelContainer(SampleData.previewContainer())
    .environment(GroupService.shared)
}
