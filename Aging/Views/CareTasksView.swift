import SwiftData
import SwiftUI

/// The family's shared to-do list for one care recipient, reachable from
/// `PersonDetailView`.
///
/// I1: everything renders from `person.liveTasks`, which is already in the
/// local store. Ticking a task off is a local write plus an outbox entry, so it
/// works in a waiting room with no signal and reaches the rest of the family
/// whenever the phone next has a network.
///
/// I6: nothing here notifies anyone. An overdue task changes where it sorts and
/// nothing else.
struct CareTasksView: View {
    let person: Person

    @Environment(\.modelContext) private var context
    @Environment(GroupService.self) private var groups

    @State private var isAddingTask = false
    @State private var editingTask: CareTask?
    @State private var showDone = false
    @State private var scope: TaskScope = .everyone

    /// Deliberately not persisted. A filter that survives relaunch is a filter
    /// people forget is on, and the failure it produces here is a sibling
    /// concluding the family has nothing left to do.
    private enum TaskScope: String, CaseIterable, Identifiable {
        case everyone, mine

        var id: String { rawValue }

        var label: String {
            switch self {
            case .everyone: return "Everyone"
            case .mine: return "Mine"
            }
        }
    }

    /// The filter is only offered once someone else is actually in the circle.
    /// Alone, this device has neither a user id nor a name to match on, so
    /// "Mine" could only ever be empty.
    private var canFilterByAssignee: Bool { groups.hasOtherMembers }

    private var visibleTasks: [CareTask] {
        let all = person.liveTasks
        guard scope == .mine, canFilterByAssignee else { return all }
        return TaskPlanner.assigned(all, to: groups.selfUserID, named: groups.selfDisplayName)
    }

    private var sections: [(bucket: CareTaskBucket, tasks: [CareTask])] {
        TaskPlanner.openSections(visibleTasks)
    }

    private var done: [CareTask] {
        TaskPlanner.recentlyCompleted(visibleTasks)
    }

    /// How many open tasks the filter is hiding. Shown rather than left implicit
    /// because an empty "Mine" and an empty list are the same picture.
    private var openCountForEveryone: Int {
        TaskPlanner.openSections(person.liveTasks).reduce(0) { $0 + $1.tasks.count }
    }

    var body: some View {
        List {
            if canFilterByAssignee {
                Section {
                    Picker("Show", selection: $scope) {
                        ForEach(TaskScope.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("tasks.scope")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0))
                .listRowSeparator(.hidden)
            }

            if sections.isEmpty, scope == .mine, canFilterByAssignee {
                Section {
                    ContentUnavailableView {
                        Label("Nothing assigned to you", systemImage: "person.crop.circle")
                    } description: {
                        Text(openCountForEveryone == 1
                             ? "There is 1 open task for \(person.displayLabel) with someone else's name on it, or nobody's."
                             : "There are \(openCountForEveryone) open tasks for \(person.displayLabel) with someone else's name on them, or nobody's.")
                    } actions: {
                        Button("Show everyone's") { scope = .everyone }
                    }
                    .listRowBackground(Color.clear)
                }
            } else if sections.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Nothing to do",
                        systemImage: "checklist",
                        description: Text("Refills, appointments to book, bills to pay: anything the family needs to keep track of for \(person.displayLabel).")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(sections, id: \.bucket) { section in
                    Section(section.bucket.label) {
                        ForEach(section.tasks) { task in
                            TaskRow(task: task, isMine: isMine(task)) { complete(task) }
                                .contentShape(Rectangle())
                                .onTapGesture { editingTask = task }
                        }
                        .onDelete { offsets in delete(section.tasks, at: offsets) }
                    }
                }
            }

            if !done.isEmpty {
                Section {
                    if showDone {
                        ForEach(done) { task in
                            DoneRow(task: task) { task.markIncomplete(in: context) }
                        }
                        .onDelete { offsets in delete(done, at: offsets) }
                    }
                } header: {
                    Button {
                        withAnimation { showDone.toggle() }
                    } label: {
                        HStack {
                            Text("Done")
                            Spacer()
                            Text(showDone ? "Hide" : "\(done.count)")
                        }
                    }
                    .buttonStyle(.plain)
                } footer: {
                    if showDone {
                        Text("Completed in the last 30 days. Everything older stays on the timeline.")
                    }
                }
            }
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingTask = true
                } label: {
                    Label("Add task", systemImage: "plus")
                }
                .accessibilityIdentifier("tasks.add")
            }
        }
        .sheet(isPresented: $isAddingTask) {
            CareTaskEditorSheet(person: person, task: nil)
        }
        .sheet(item: $editingTask) { task in
            CareTaskEditorSheet(person: person, task: task)
        }
    }

    private func complete(_ task: CareTask) {
        task.markComplete(by: CareTaskAuthor.name(from: groups), in: context)
    }

    private func isMine(_ task: CareTask) -> Bool {
        guard canFilterByAssignee else { return false }
        return TaskPlanner.isAssigned(task, to: groups.selfUserID, named: groups.selfDisplayName)
    }

    /// Tombstones rather than hard-deletes: a row that only disappears locally
    /// would never be pushed, so the delete would live and die on this phone.
    private func delete(_ tasks: [CareTask], at offsets: IndexSet) {
        for index in offsets {
            tasks[index].tombstone(in: context)
        }
    }
}

// MARK: - Author

/// Whose name goes on a task this device writes.
///
/// A solo caregiver with no group has no member list and no name to use, and
/// "You" is what the rest of the app already writes in that case
/// (`CareEventsView`, `TodayView`). Once a family exists, the real name is
/// used, because "You" on a sibling's phone names the wrong person.
enum CareTaskAuthor {
    @MainActor
    static func name(from groups: GroupService) -> String {
        let name = groups.selfDisplayName
        return name.isEmpty ? "You" : name
    }
}

// MARK: - Rows

private struct TaskRow: View {
    let task: CareTask
    /// Whether this row is the reader's own errand. Passed in rather than
    /// resolved here so the row stays a pure view and the matching rule lives in
    /// one place.
    let isMine: Bool
    let onComplete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(task.title) done")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if task.priority == .high {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(task.title)
                        .font(.body.weight(.medium))
                }

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let dueAt = task.dueAt {
            parts.append(dueAt.formatted(date: .abbreviated, time: .omitted))
        }
        if !task.assigneeName.isEmpty {
            // The reader's own name on the row tells them nothing they did not
            // already know, and reads as a third party when skimming.
            parts.append(isMine ? "You" : task.assigneeName)
        }
        if task.recurrence != .never {
            parts.append(task.recurrence.shortLabel)
        }
        return parts.joined(separator: " · ")
    }
}

private struct DoneRow: View {
    let task: CareTask
    let onReopen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onReopen) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reopen \(task.title)")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(color: .secondary)
                    .foregroundStyle(.secondary)
                if let completedAt = task.completedAt {
                    Text(completedLabel(completedAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func completedLabel(_ date: Date) -> String {
        let when = date.formatted(date: .abbreviated, time: .omitted)
        guard !task.completedByName.isEmpty else { return when }
        return "\(when) · \(task.completedByName)"
    }
}

// MARK: - Editor

struct CareTaskEditorSheet: View {
    let person: Person
    let task: CareTask?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(GroupService.self) private var groups

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate = false
    @State private var dueAt = Date()
    @State private var priority: CareTaskPriority = .normal
    @State private var recurrence: CareTaskRecurrence = .never
    @State private var assigneeName = ""
    @State private var assigneeUserID: UUID?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only the members this device has already loaded, and only the ones with
    /// a name worth writing down. The field stays a plain text field so
    /// assigning someone still works on a phone that has never been online
    /// since launch.
    private var assignableMembers: [GroupMember] {
        groups.members.filter { !$0.displayName.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                        .accessibilityIdentifier("task-editor.title")
                }

                Section {
                    Toggle("Due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueAt, displayedComponents: [.date])
                        Picker("Repeat", selection: $recurrence) {
                            ForEach(CareTaskRecurrence.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .accessibilityIdentifier("task-editor.repeat")
                    }
                } footer: {
                    if hasDueDate, recurrence != .never {
                        Text("Ticking this off adds the next one automatically. The completed task stays in the history.")
                    }
                }

                Section {
                    Picker("Priority", selection: $priority) {
                        ForEach(CareTaskPriority.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        TextField("Who's doing it", text: $assigneeName)
                            .accessibilityIdentifier("task-editor.assignee")
                        if !assignableMembers.isEmpty {
                            Menu {
                                ForEach(assignableMembers) { member in
                                    Button(member.resolvedName) {
                                        assigneeName = member.displayName
                                        assigneeUserID = member.id
                                    }
                                }
                            } label: {
                                Image(systemName: "person.crop.circle.badge.plus")
                            }
                            .accessibilityLabel("Pick from the family")
                            .accessibilityIdentifier("task-editor.assignee-picker")
                        }
                    }
                } footer: {
                    // Still true and still worth saying: the list filters by
                    // assignee now, which is a long way from telling anyone.
                    Text("Assigning someone marks the task as theirs, so they can filter the list down to it. Nobody is notified.")
                }

                Section("Notes") {
                    TextField("Anything worth remembering", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(task == nil ? "New Task" : "Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let task else { return }
        title = task.title
        notes = task.notes
        hasDueDate = task.dueAt != nil
        dueAt = task.dueAt ?? Date()
        priority = task.priority
        recurrence = task.recurrence
        assigneeName = task.assigneeName
        assigneeUserID = task.assigneeUserID
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }

        let target = task ?? {
            let new = CareTask(
                title: trimmedTitle,
                createdByName: CareTaskAuthor.name(from: groups),
                person: person
            )
            context.insert(new)
            return new
        }()

        target.title = trimmedTitle
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.dueAt = hasDueDate ? dueAt : nil
        target.priority = priority
        // A repeat with no due date has nothing to repeat from.
        target.recurrence = hasDueDate ? recurrence : .never
        let trimmedAssignee = assigneeName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.assigneeName = trimmedAssignee
        // Clearing or retyping the name drops the id rather than leaving it
        // pointing at whoever was picked from the menu three edits ago.
        target.assigneeUserID = trimmedAssignee.isEmpty ? nil : assigneeUserID
        target.recordLocalChange(in: context)

        dismiss()
    }
}

#Preview {
    NavigationStack {
        CareTasksView(person: SampleData.previewPerson())
    }
    .modelContainer(SampleData.previewContainer())
    .environment(GroupService.shared)
}
