import SwiftData
import SwiftUI

struct TodayView: View {
    // Tombstoned rows stay in the store until the outbox has pushed them, so
    // every list of people has to filter them out.
    @Query(filter: #Predicate<Person> { $0.deletedAt == nil }, sort: \Person.createdAt)
    private var people: [Person]
    @Environment(\.modelContext) private var context
    @Environment(GroupService.self) private var groups
    @Environment(CheckInService.self) private var checkIn
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedPersonID: UUID?
    @State private var quickAction: QuickAction?
    @State private var isEditingDetails = false
    @State private var isAddingMedication = false
    @State private var setupHidden = false
    @State private var setupVersion = 0
    @State private var dismissedSteps: Set<SetupStep.Kind> = []
    @State private var destination: TodayDestination?

    /// The two big cards at the bottom. A `Button` driving one destination for
    /// the same reason the chips are: a `NavigationLink` wrapping a card draws
    /// the system chevron outside the card, beside the one the card already
    /// has.
    private enum TodayDestination: Hashable, Identifiable {
        case emergencyCard
        case fullRecord

        var id: Self { self }
    }

    /// Whoever was picked, otherwise the first person the family actually
    /// shares. The fallback used to be `people.first`, which on a phone holding
    /// both a private record and a joined circle could open Today on the
    /// private one and leave it looking like the shared record everybody else
    /// was reading. An explicit pick is always honoured; only the default is
    /// opinionated.
    private var selectedPerson: Person? {
        if let selectedPersonID, let picked = people.first(where: { $0.id == selectedPersonID }) {
            return picked
        }
        if let activeGroupID = groups.activeGroupID,
           let shared = people.first(where: { $0.groupID == activeGroupID }) {
            return shared
        }
        return people.first
    }

    /// True for a row that is not part of the circle this device belongs to.
    /// Marked in the picker so "which record am I looking at" is answerable
    /// without leaving the screen.
    private func isPrivate(_ person: Person) -> Bool {
        guard let activeGroupID = groups.activeGroupID else { return false }
        return person.groupID != activeGroupID
    }

    var body: some View {
        NavigationStack {
            Group {
                if let person = selectedPerson {
                    content(for: person)
                } else {
                    ContentUnavailableView(
                        "No one added yet",
                        systemImage: "person.badge.plus",
                        description: Text("Add someone on the Care tab.")
                    )
                }
            }
            .navigationTitle("Today")
            .navigationDestination(item: $quickAction) { action in
                if let person = selectedPerson {
                    quickDestination(for: action, person: person)
                }
            }
            .navigationDestination(item: $destination) { target in
                if let person = selectedPerson {
                    switch target {
                    case .emergencyCard: EmergencyCardView(person: person)
                    case .fullRecord: PersonDetailView(person: person)
                    }
                }
            }
            .sheet(isPresented: $isEditingDetails) {
                if let person = selectedPerson {
                    PersonDetailsEditorSheet(person: person)
                }
            }
            .sheet(isPresented: $isAddingMedication) {
                if let person = selectedPerson {
                    MedicationEditorSheet(person: person)
                }
            }
            .toolbar {
                if people.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        personMenu
                    }
                }
            }
        }
        .onAppear { refreshSetupVisibility() }
        .onChange(of: selectedPersonID) { _, _ in refreshSetupVisibility() }
    }

    private func refreshSetupVisibility() {
        guard let person = selectedPerson else {
            setupHidden = false
            dismissedSteps = []
            return
        }
        setupHidden = SetupCardPreferences.isHidden(personID: person.id)
        dismissedSteps = SetupStepPreferences.dismissed(personID: person.id)
    }

    private var personMenu: some View {
        Menu {
            ForEach(people) { person in
                Button {
                    selectedPersonID = person.id
                } label: {
                    Label(
                        isPrivate(person) ? "\(person.displayLabel) (only on this phone)" : person.displayLabel,
                        systemImage: person.id == selectedPerson?.id ? "checkmark" : "person"
                    )
                }
            }
        } label: {
            Text(selectedPerson?.displayLabel ?? "Person")
                .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private func content(for person: Person) -> some View {
        let slots = ScheduleEngine.slots(for: person, on: Date())
        let runningLow = runningLowMedications(for: person)
        // Overdue and due-today only. Showing work that is not due yet is how a
        // "what's left" list stops being believed.
        let tasksDue = TaskPlanner.dueNow(person.liveTasks)
        let billsDue = BillPlanner.needingAttention(person.liveBills)

        List {
            // First, not last. It used to sit under everything else on the
            // reasoning that getting set up is not what today is, and that is
            // true of a record with a month of history in it and wrong of the
            // one screen a new user ever sees: a checklist below the fold is a
            // checklist nobody works through. It is dismissible a row at a
            // time and as a whole, which is what makes putting it here fair.
            if !setupHidden, !visibleSetupSteps(for: person).isEmpty {
                Section {
                    SetupProgressCard(
                        personLabel: person.displayLabel,
                        steps: visibleSetupSteps(for: person),
                        onSelect: { perform($0, for: person) },
                        onDismissStep: { step in
                            SetupStepPreferences.dismiss(step.kind, personID: person.id)
                            dismissedSteps.insert(step.kind)
                        },
                        onHide: {
                            SetupCardPreferences.setHidden(true, personID: person.id)
                            setupHidden = true
                        }
                    )
                    .accessibilityIdentifier("today.setup-card")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 10, trailing: 0))
                .listRowSeparator(.hidden)
            }

            // The app's range has to be visible on the screen people actually
            // open. Before this row, a caregiver could use the app for a month
            // without discovering it logs blood pressure, keeps the pharmacy's
            // number or holds a note about last week's fall.
            Section {
                quickActions(for: person)
            } header: {
                Text("Log or look up")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0))
            .listRowSeparator(.hidden)

            // Only once a check-in has been agreed. Set-up lives on the hub and
            // stays there; what belongs on the daily screen is the answer to
            // "has she pressed it today", which was previously two taps into a
            // settings screen on another tab.
            //
            // A statement about a button, never about the person (I6).
            if checkIn.settings(for: person)?.enabled == true {
                Section {
                    Button {
                        quickAction = .feature(.checkIn)
                    } label: {
                        let checkedIn = checkIn.hasCheckedInToday(person)
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(checkedIn ? "Checked in today" : "No check-in yet today")
                                    .font(.body.weight(.medium))
                                if let last = checkIn.lastCheckIn(for: person) {
                                    Text("Last at \(last.pressedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: checkedIn ? "checkmark.circle.fill" : "hand.wave")
                                .foregroundStyle(checkedIn ? .green : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.check-in")
                } header: {
                    Text("Check-in")
                }
            }

            if !tasksDue.isEmpty {
                Section("Tasks") {
                    ForEach(tasksDue) { task in
                        // Deliberately not filtered to the reader. Today is
                        // "what is left for her", and a list that hides a
                        // sibling's overdue errand answers a different
                        // question. Whose it is goes on the row instead.
                        TodayTaskRow(task: task, isMine: isMine(task)) {
                            task.markComplete(by: CareTaskAuthor.name(from: groups), in: context)
                        }
                    }
                }
            }

            if !runningLow.isEmpty {
                Section("Running low") {
                    ForEach(runningLow, id: \.id) { medication in
                        RefillRow(medication: medication)
                    }
                }
            }


            // Nothing at all until there is a medication to have doses of.
            // A "Doses" heading over "No medications yet" is a section about
            // an absence: it takes the top of the daily screen to say that a
            // feature exists, on the one record where the setup card above is
            // already saying exactly that and offering the button. Most people
            // this app is for have medications; the empty case should not be
            // the one the layout is built around.
            if !person.activeMedications.isEmpty {
                Section("Today's doses") {
                    if slots.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nothing scheduled today")
                                .font(.body.weight(.medium))
                            Text("Everything \(person.displayLabel) takes is as-needed.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    } else {
                        ForEach(slots) { slot in
                            DoseRow(slot: slot, person: person) { status in
                                if let status {
                                    record(status, for: slot, person: person)
                                } else {
                                    clear(slot, person: person)
                                }
                            }
                        }
                    }
                }
            }


            // Below the doses, deliberately. Bills is a weekly errand and the
            // dose list is the several-times-a-day job this app exists for, so
            // bills must never push it down the screen. It also kept the dose
            // rows inside the `List`'s lazily built window on a seeded day.
            if !billsDue.isEmpty {
                Section("Bills") {
                    ForEach(billsDue) { bill in
                        TodayBillRow(bill: bill) {
                            bill.markPaid(by: CareTaskAuthor.name(from: groups), in: context)
                        }
                    }
                }
            }

            // Two cards rather than two list rows. These are the most important
            // destinations in the app and they were carrying the same visual
            // weight as a settings toggle.
            Section {
                VStack(spacing: 12) {
                    Button {
                        destination = .emergencyCard
                    } label: {
                        BigNavCard(
                            title: "Emergency card",
                            detail: "One page for the ER: \(person.displayLabel)'s meds, allergies and contacts. Works with no signal.",
                            symbol: "cross.case.fill",
                            tint: .red
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.emergency-card")

                    Button {
                        destination = .fullRecord
                    } label: {
                        BigNavCard(
                            title: "\(person.displayLabel)'s full record",
                            detail: "Medications, tasks, vitals, visits, providers, contacts, notes and history.",
                            symbol: "person.text.rectangle.fill",
                            tint: .accentColor
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.medications")
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 24, trailing: 0))
            .listRowSeparator(.hidden)
        }
    }

    /// The steps still worth showing for this person: undone, and not waved
    /// away.
    private func visibleSetupSteps(for person: Person) -> [SetupStep] {
        let steps = SetupChecklist.visible(setupSteps(for: person), dismissed: dismissedSteps)
        return SetupChecklist.isFinished(steps) ? [] : steps
    }

    /// A row of one-tap ways into the rest of the app.
    ///
    /// Chips rather than a second list: a list row reads as "here is a thing
    /// you have", a chip reads as "here is something you can do", and the
    /// complaint this answers was about what the app can do.
    ///
    /// Sized to share the width rather than to scroll. The seven fixed-width
    /// chips that came before overflowed the screen, so the last three were
    /// invisible and the labels of the visible ones ran into each other, which
    /// is the same discoverability failure in a smaller box.
    private func quickActions(for person: Person) -> some View {
        LazyVGrid(columns: quickActionColumns, spacing: 14) {
            ForEach(QuickAction.todayRow) { action in
                quickActionEntry(action, person: person)
            }
        }
        .padding(.vertical, 4)
    }

    private var quickActionColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    private func setupSteps(for person: Person) -> [SetupStep] {
        _ = setupVersion
        return SetupChecklist.steps(
            for: person,
            remindersEnabled: DoseReminderPreferences.isEnabled(personID: person.id),
            hasSharedWithFamily: groups.hasSharedWithFamily,
            hasCheckIn: checkIn.settings(for: person)?.enabled == true
        )
    }

    private func perform(_ step: SetupStep, for person: Person) {
        switch step.kind {
        case .addMedication:
            isAddingMedication = true
        case .doseReminders:
            DoseReminderPreferences.setEnabled(true, personID: person.id)
            setupVersion += 1
            Task {
                let granted = await NotificationService.shared.requestAuthorization()
                if !granted {
                    DoseReminderPreferences.setEnabled(false, personID: person.id)
                    setupVersion += 1
                }
                await DoseReminderScheduler.refresh(in: context)
            }
        case .healthDetails:
            isEditingDetails = true
        case .emergencyContact:
            quickAction = .feature(.contacts)
        case .inviteFamily:
            navigator.showFamilyInvite()
        case .checkIn:
            quickAction = .feature(.checkIn)
        }
    }

    /// Every chip pushes a screen, including Medical.
    ///
    /// Medical used to drop a menu instead. One tap gesture producing two
    /// different kinds of thing is disorienting on its own, and the menu also
    /// offered six bare words with no indication of what was in any of them.
    /// `MedicalRecordView` is the same six, as tiles that say what they hold.
    private func quickActionEntry(_ action: QuickAction, person: Person) -> some View {
        // A button feeding one `navigationDestination` rather than a link each:
        // links nested this deep inside a `List` row do not reliably push.
        Button {
            open(action, person: person)
        } label: {
            QuickActionChip(
                title: action.title,
                symbol: action.symbol,
                tint: AppTheme.color(forFeatureIndex: action.colorIndex)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.quick.\(action.id)")
    }

    /// Health details is the one feature whose editor is a sheet rather than a
    /// screen, so it presents where everything else pushes.
    private func open(_ action: QuickAction, person: Person) {
        if case .feature(.healthDetails) = action {
            isEditingDetails = true
        } else {
            quickAction = action
        }
    }

    @ViewBuilder
    private func quickDestination(for action: QuickAction, person: Person) -> some View {
        switch action {
        case .medical:
            MedicalRecordView(person: person)
        case .feature(.healthDetails):
            // Health details is a sheet, not a screen.
            EmptyView()
        case .feature(.medications):
            PersonDetailView(person: person)
        case .feature(.tasks):
            CareTasksView(person: person)
        case .feature(.vitals):
            VitalsView(person: person)
        case .feature(.visits):
            VisitsView(person: person)
        case .feature(.providers):
            ProvidersView(person: person)
        case .feature(.incidents):
            CareEventsView(person: person)
        case .feature(.timeline):
            TimelineView(person: person)
        case .feature(.notes):
            CareNotesView(person: person)
        case .feature(.bills):
            BillsView(person: person)
        case .feature(.contacts):
            EmergencyContactsView(person: person)
        case .feature(.checkIn):
            CheckInSettingsView(person: person)
        }
    }

    private func record(_ status: DoseStatus, for slot: DoseSlot, person: Person) {
        guard let medication = person.liveMedications.first(where: { $0.id == slot.medicationID }) else { return }

        let calendar = Calendar.current
        // Searched across `doses`, not `liveDoses`, so a slot that was undone
        // is reused rather than inserted a second time. `DoseLog.id` is
        // derived from (medication, scheduled time), so a fresh row for the
        // same slot would carry the id the tombstone still holds, and the push
        // would have two rows to choose from for one server key.
        if let existing = medication.doses.first(where: {
            calendar.isDate($0.scheduledAt, equalTo: slot.scheduledAt, toGranularity: .minute)
        }) {
            // Taken again after an undo: the row comes back rather than a new
            // one appearing beside it.
            let wasTaken = existing.deletedAt == nil && existing.status == .taken
            existing.deletedAt = nil
            existing.status = status
            existing.recordedAt = Date()
            // Correcting a logged dose has to move the count too, or a mistap
            // leaves the on-hand quantity permanently wrong.
            if !wasTaken, status == .taken {
                medication.decrementForDoseTaken()
                medication.recordLocalChange(in: context)
            } else if wasTaken, status != .taken {
                medication.restoreForDoseUntaken()
                medication.recordLocalChange(in: context)
            }
            existing.recordLocalChange(in: context)
            return
        }

        let log = DoseLog(
            scheduledAt: slot.scheduledAt,
            status: status,
            // The member's own name once a family exists, the same as tasks
            // and notes. "You" on a sibling's phone names the wrong person,
            // and "who marked this taken" is the question a shared medication
            // record has to be able to answer.
            recordedBy: CareTaskAuthor.name(from: groups),
            medication: medication
        )
        context.insert(log)
        log.recordLocalChange(in: context)

        // Only a dose logged for the first time on this device counts against
        // what's on hand. A dose that arrives later through sync already
        // happened on the device that logged it (see `applyDoseLog`), so this
        // must never run there too.
        if status == .taken {
            medication.decrementForDoseTaken()
            medication.recordLocalChange(in: context)
        }
    }

    /// Puts a dose back to "not recorded yet".
    ///
    /// The only correction that existed was a swipe labelled Skip, which
    /// records a different fact rather than undoing the wrong one: a mistap on
    /// Taken became a deliberate "they skipped it" in the history. This
    /// tombstones the log so the slot reads as untouched again, and gives the
    /// tablet back to the refill count.
    private func clear(_ slot: DoseSlot, person: Person) {
        guard let medication = person.liveMedications.first(where: { $0.id == slot.medicationID }),
              let existing = medication.liveDoses.first(where: {
                  Calendar.current.isDate($0.scheduledAt, equalTo: slot.scheduledAt, toGranularity: .minute)
              })
        else { return }

        if existing.status == .taken {
            medication.restoreForDoseUntaken()
            medication.recordLocalChange(in: context)
        }
        existing.tombstone(in: context)
    }

    /// A one-line row for a bill that is late or due this week: tick it off, or
    /// open the full list. Same shape and same reasoning as `TodayTaskRow`.
    private func runningLowMedications(for person: Person) -> [Medication] {
        person.activeMedications.filter { medication in
            guard let daysRemaining = medication.daysRemaining else { return false }
            return daysRemaining <= Double(medication.refillThresholdDays)
        }
    }

    /// Whose errand this is. Only meaningful once someone else is in the circle;
    /// alone, every task is the reader's and saying so on every row is noise.
    private func isMine(_ task: CareTask) -> Bool {
        guard groups.hasOtherMembers else { return false }
        return TaskPlanner.isAssigned(task, to: groups.selfUserID, named: groups.selfDisplayName)
    }
}

/// The Today version of a bill row: mark it paid, or leave it. Editing lives on
/// the Bills screen, the same way editing a task does.
///
/// "Paid" here records that a human says they paid it. Nothing in this app pays
/// anything (I6).
private struct TodayBillRow: View {
    let bill: Bill
    let onPaid: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPaid) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(bill.payee) paid")

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
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        guard let dueAt = bill.dueAt else { return bill.category.label }
        let calendar = Calendar.current
        if calendar.startOfDay(for: dueAt) < calendar.startOfDay(for: Date()) {
            return "Was due \(dueAt.formatted(date: .abbreviated, time: .omitted))"
        }
        if calendar.isDateInToday(dueAt) { return "Due today" }
        return "Due \(dueAt.formatted(date: .abbreviated, time: .omitted))"
    }
}

/// A one-line version of the task row: tick it off or open the full list. The
/// Today tab is a place to act, not a place to edit.
private struct TodayTaskRow: View {
    let task: CareTask
    let isMine: Bool
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(task.title) done")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.body.weight(.medium))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        var parts: [String] = []
        // Due-today used to print nothing, so a task due today and a task with
        // no date at all read identically once an assignee was on the row.
        if let dueAt = task.dueAt {
            let calendar = Calendar.current
            if dueAt < calendar.startOfDay(for: Date()) {
                parts.append("Was due \(dueAt.formatted(date: .abbreviated, time: .omitted))")
            } else if calendar.isDateInToday(dueAt) {
                parts.append("Due today")
            }
        }
        if !task.assigneeName.isEmpty {
            parts.append(isMine ? "You" : task.assigneeName)
        }
        return parts.joined(separator: " · ")
    }
}

private struct RefillRow: View {
    let medication: Medication

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(medication.displayName)
                    .font(.body.weight(.medium))
                Text(daysLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 4)
    }

    private var daysLabel: String {
        if medication.isOutOfStock { return "None left" }
        guard let daysRemaining = medication.daysRemaining else { return "Refill soon" }
        let days = max(0, Int(daysRemaining.rounded()))
        guard days > 0 else { return "Last dose today" }
        return days == 1 ? "1 day left" : "\(days) days left"
    }
}

private struct DoseRow: View {
    let slot: DoseSlot
    let person: Person
    /// Nil means "put this back to not recorded yet".
    let onRecord: (DoseStatus?) -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(slot.medicationName)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(slot.scheduledAt.formatted(date: .omitted, time: .shortened))
                    if !slot.strength.isEmpty {
                        Text("·")
                        Text(slot.strength)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let status = slot.status {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(status.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(status == .taken ? .green : .secondary)
                    if !slot.recordedBy.isEmpty {
                        Text(slot.recordedBy)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button("Taken") { onRecord(.taken) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            // Undo comes first, and only once there is something to undo.
            // Skip records a different fact; it never repaired a mistap.
            if slot.status != nil {
                Button("Undo") { onRecord(nil) }
                    .tint(.gray)
            }
            Button("Skip") { onRecord(.skipped) }
                .tint(.orange)
        }
    }
}

#Preview {
    TodayView()
        .modelContainer(SampleData.previewContainer())
        .environment(GroupService.shared)
        .environment(CheckInService.shared)
        .environment(DeviceModeService.shared)
}
