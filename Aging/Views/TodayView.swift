import StoreKit
import SwiftData
import SwiftUI
import UIKit

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
    @Environment(AuthService.self) private var auth
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.openURL) private var openURL

    @State private var scopeSelection: TodayScope?
    @State private var quickAction: QuickAction?
    @State private var isEditingDetails = false
    @State private var isAddingMedication = false
    @State private var setupHidden = false
    @State private var setupVersion = 0
    @State private var showNotificationsBlocked = false
    @State private var undo: UndoableAction?
    @State private var isAskingForReview = false
    /// Bumped on every tick-off so the phone confirms it in the hand. Doses,
    /// tasks and bills gave no feedback at all; only the check-in button did.
    @State private var confirmations = 0
    @State private var dismissedSteps: Set<SetupStep.Kind> = []
    @State private var destination: TodayDestination?
    @State private var notificationRoute = NotificationRoute.shared

    /// The two big cards at the bottom. A `Button` driving one destination for
    /// the same reason the chips are: a `NavigationLink` wrapping a card draws
    /// the system chevron outside the card, beside the one the card already
    /// has.
    private enum TodayDestination: Hashable, Identifiable {
        case emergencyCard
        case fullRecord
        case appointments
        /// Named, because Everyone mode has no selected person and the card is
        /// the one screen that must never need a person to be selected first.
        case emergencyCardFor(UUID)

        var id: Self { self }
    }

    /// Whose day this screen is showing.
    ///
    /// `.everyone` exists only once there is more than one person to look
    /// after. A solo caregiver never sees it, never sees the picker, and gets
    /// the screen they have always had: the aggregate is the answer to a
    /// question they do not have.
    private enum TodayScope: Hashable {
        case everyone
        case person(UUID)
    }

    /// Who a single-person phone opens on: the first person the family actually
    /// shares. This used to be `people.first`, which on a phone holding both a
    /// private record and a joined circle could open Today on the private one
    /// and leave it looking like the shared record everybody else was reading.
    /// Only the default is opinionated; an explicit pick always wins.
    private var defaultPerson: Person? {
        if let activeGroupID = groups.activeGroupID,
           let shared = people.first(where: { $0.groupID == activeGroupID }) {
            return shared
        }
        return people.first
    }

    /// The resolved scope, falling back rather than trusting the stored one.
    ///
    /// A stored pick can name a person who has since been deleted or who was
    /// never on this device, and `.everyone` is meaningless once a circle is
    /// back down to one person, so both are re-checked against the current
    /// list every time.
    private var scope: TodayScope {
        switch scopeSelection {
        case .person(let id) where people.contains(where: { $0.id == id }):
            return .person(id)
        case .everyone where people.count > 1:
            return .everyone
        default:
            break
        }
        // With more than one person, the honest answer to "what is left today"
        // spans all of them. Opening on one of them is how Dad's overdue 8am
        // dose stayed invisible to someone looking at Mom.
        if people.count > 1 { return .everyone }
        if let defaultPerson { return .person(defaultPerson.id) }
        return .everyone
    }

    /// The person every sheet, destination and quick action hangs off. Nil in
    /// Everyone mode, where those are not offered: a quick action needs to know
    /// whose record it is writing to, and guessing is how the wrong parent gets
    /// a blood pressure reading.
    private var selectedPerson: Person? {
        guard case .person(let id) = scope else { return nil }
        return people.first { $0.id == id }
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
                if people.isEmpty {
                    ContentUnavailableView(
                        "No one added yet",
                        systemImage: "person.badge.plus",
                        description: Text("Add someone on the Care tab.")
                    )
                } else if case .everyone = scope {
                    everyoneContent
                } else if let person = selectedPerson {
                    content(for: person)
                }
            }
            .navigationTitle("Today")
            .navigationDestination(item: $quickAction) { action in
                if let person = selectedPerson {
                    quickDestination(for: action, person: person)
                }
            }
            .navigationDestination(item: $destination) { target in
                switch target {
                case .emergencyCardFor(let id):
                    if let person = people.first(where: { $0.id == id }) {
                        EmergencyCardView(person: person)
                    }
                default:
                    if let person = selectedPerson {
                        switch target {
                        case .emergencyCard: EmergencyCardView(person: person)
                        case .fullRecord: PersonDetailView(person: person)
                        case .appointments: VisitsView(person: person)
                        case .emergencyCardFor: EmptyView()
                        }
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
            .notificationsBlockedAlert(isPresented: $showNotificationsBlocked)
            .sheet(isPresented: $isAskingForReview) {
                ReviewPromptSheet { outcome in
                    switch outcome {
                    case .notNow:
                        ReviewPrompt.markAsked()
                    case .wantsToRate:
                        // Apple's own prompt, which is the only thing that can
                        // actually leave a rating in place. It frequently shows
                        // nothing at all, which is why saying yes is recorded
                        // as a soft defer rather than as settled.
                        ReviewPrompt.markSoftDeferred()
                        requestAppReview()
                    case .sendingFeedback:
                        ReviewPrompt.markSettled()
                        openSupportMail()
                    }
                }
            }
            .sensoryFeedback(.success, trigger: confirmations)
            // Explicitly zero-height and hit-transparent when there is nothing
            // to undo. A bare `if` inside `safeAreaInset` leaves a container
            // that can still sit over the tab bar underneath this stack and
            // eat taps meant for it, which reads as the Care tab having stopped
            // working. Nothing about the banner is worth that.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Group {
                    if let undo {
                        UndoBanner(action: undo) {
                            undo.perform()
                            withAnimation(.snappy) { self.undo = nil }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Color.clear.frame(height: 0)
                    }
                }
                .allowsHitTesting(undo != nil)
            }
            .toolbar {
                if people.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        personMenu
                    }
                }
            }
        }
        .onAppear {
            applyPendingNotificationRoute()
            refreshSetupVisibility()
            considerAskingForReview()
        }
        .onChange(of: scopeSelection) { _, _ in refreshSetupVisibility() }
        .onChange(of: notificationRoute.pendingPersonID) { _, _ in
            applyPendingNotificationRoute()
        }
    }

    /// Honours a tapped reminder by scoping to the person it named.
    ///
    /// Consumed rather than observed, so the same tap cannot move someone off
    /// the screen they deliberately opened later. Also checked on appear,
    /// because a tap that arrives while another tab is showing fires no
    /// `onChange` here.
    private func applyPendingNotificationRoute() {
        guard let pending = notificationRoute.pendingPersonID else { return }
        guard people.contains(where: { $0.id == pending }) else {
            // The reminder outlived the record: a person deleted on another
            // device, or one this phone has not synced yet. Drop it rather than
            // leaving it queued to fire on a later, unrelated appearance.
            _ = notificationRoute.consume()
            return
        }
        _ = notificationRoute.consume()
        scopeSelection = .person(pending)
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
            Button {
                scopeSelection = .everyone
            } label: {
                Label(
                    "Everyone",
                    systemImage: isEveryone ? "checkmark" : "person.2"
                )
            }

            Divider()

            ForEach(people) { person in
                Button {
                    scopeSelection = .person(person.id)
                } label: {
                    Label(
                        isPrivate(person) ? "\(person.displayLabel) (only on this phone)" : person.displayLabel,
                        systemImage: person.id == selectedPerson?.id ? "checkmark" : "person"
                    )
                }
                // The person's name also appears as a section heading in
                // Everyone mode, so a UI test matching on the label alone finds
                // two elements and taps neither.
                .accessibilityIdentifier("today.person-option.\(person.displayLabel)")
            }
        } label: {
            Text(isEveryone ? "Everyone" : (selectedPerson?.displayLabel ?? "Person"))
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityIdentifier("today.person-picker")
    }

    private var isEveryone: Bool {
        if case .everyone = scope { return true }
        return false
    }

    // MARK: - Everyone

    /// Today across every person, grouped by person.
    ///
    /// Only reachable when there is more than one person, and deliberately not
    /// a copy of the single-person screen repeated N times. The setup checklist
    /// and the quick-action row are per-person jobs and stay on the per-person
    /// screen; what belongs here is the work that is outstanding and a way into
    /// whoever it belongs to. Doses and tasks are actionable in place, because
    /// having to switch person to tick off Dad's tablet is the whole problem
    /// this screen exists to fix.
    private var everyoneContent: some View {
        let digests = TodayDigest.build(for: people, on: Date(), checkInState: checkInState)
        let outstanding = digests.filter { !$0.isClear }
        // Named `settled` and not `clear`: `clear(_:person:)` is the undo path
        // for a dose a few lines below, and shadowing it here silently turns
        // that call site into a reference to this array.
        let settled = digests.filter(\.isClear)

        return List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(TodayDigest.headline(for: digests))
                        .font(.title3.weight(.semibold))
                    Text(peopleSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("today.everyone-headline")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            // One tap from the default screen to any card in the family, and
            // above the day's work rather than under it.
            //
            // Everyone mode is what a phone with two people opens on, and it
            // used to carry no route to a card at all: the person had to be
            // picked out of a toolbar menu first, then the card found at the
            // bottom of their day. That is a fine amount of work for a
            // caregiver and far too much for the paramedic they have just
            // handed the phone to.
            Section("Emergency cards") {
                ForEach(people) { person in
                    Button {
                        destination = .emergencyCardFor(person.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "cross.case.fill")
                                .foregroundStyle(.red)
                                .frame(width: 22)
                            Text(person.displayLabel)
                                .font(.body.weight(.medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today.everyone.emergency-card.\(person.displayLabel)")
                }
            }

            ForEach(outstanding) { digest in
                Section {
                    // First in the section, because it is the only line here
                    // that is about the person rather than about a list, and
                    // the question the weekly sibling opened the app to ask.
                    // Not tappable to "complete": nobody may press somebody
                    // else's check-in, so this states what was recorded and
                    // goes no further (I6).
                    if digest.checkInOutstanding {
                        Label {
                            Text("No check-in yet today")
                                .font(.body.weight(.medium))
                        } icon: {
                            Image(systemName: "hand.wave")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("today.everyone.check-in")
                    }

                    ForEach(digest.pendingSlots) { slot in
                        DoseRow(slot: slot, person: digest.person) { status in
                            if let status {
                                record(status, for: slot, person: digest.person)
                            } else {
                                clear(slot, person: digest.person)
                            }
                        }
                    }

                    ForEach(digest.tasksDue) { task in
                        TodayTaskRow(task: task, isMine: isMine(task)) {
                            complete(task)
                        }
                    }

                    ForEach(digest.appointments) { visit in
                        AppointmentRow(visit: visit)
                    }

                    // Counts rather than rows: a refill and a bill are errands
                    // for later in the week, and spelling them out here buries
                    // the doses that are for right now.
                    if !digest.runningLow.isEmpty || !digest.billsDue.isEmpty {
                        Button {
                            scopeSelection = .person(digest.person.id)
                        } label: {
                            Label(
                                laterWorkLabel(for: digest),
                                systemImage: "tray.full"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    personSectionHeader(for: digest)
                }
            }

            // Named, not hidden. A person who silently vanishes off the daily
            // screen reads as a record that has gone missing, and "nothing due"
            // is the answer a caregiver came here for.
            if !settled.isEmpty {
                Section("Nothing due today") {
                    ForEach(settled) { digest in
                        Button {
                            scopeSelection = .person(digest.person.id)
                        } label: {
                            HStack {
                                Text(digest.person.displayLabel)
                                    .font(.body.weight(.medium))
                                Text(digest.statusLine)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// What `TodayDigest` cannot work out on its own. Check-in settings and
    /// presses live in a service, not on the models, and the Everyone screen is
    /// the one that has to answer "is Mom OK?" without switching person first.
    private func checkInState(_ person: Person) -> (enabled: Bool, checkedIn: Bool) {
        (
            enabled: checkIn.settings(for: person)?.enabled == true,
            checkedIn: checkIn.hasCheckedInToday(person)
        )
    }

    private var peopleSummary: String {
        let count = people.count
        return count == 1 ? "1 person" : "\(count) people"
    }

    private func laterWorkLabel(for digest: PersonDigest) -> String {
        var parts: [String] = []
        if !digest.runningLow.isEmpty {
            parts.append(digest.runningLow.count == 1 ? "1 running low" : "\(digest.runningLow.count) running low")
        }
        if !digest.billsDue.isEmpty {
            parts.append(digest.billsDue.count == 1 ? "1 bill due" : "\(digest.billsDue.count) bills due")
        }
        return parts.joined(separator: " · ")
    }

    /// The person's name, as a way into their own screen. Tapping it switches
    /// the scope rather than pushing, so the picker in the toolbar and the
    /// heading agree about where you now are.
    private func personSectionHeader(for digest: PersonDigest) -> some View {
        Button {
            scopeSelection = .person(digest.person.id)
        } label: {
            HStack(spacing: 6) {
                Text(digest.person.displayLabel)
                    .font(.subheadline.weight(.semibold))
                if !digest.overdueSlots.isEmpty {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("overdue")
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .textCase(nil)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func content(for person: Person) -> some View {
        let slots = ScheduleEngine.slots(for: person, on: Date())
        let runningLow = runningLowMedications(for: person)
        // Overdue and due-today only. Showing work that is not due yet is how a
        // "what's left" list stops being believed.
        let tasksDue = TaskPlanner.dueNow(person.liveTasks)
        let billsDue = BillPlanner.needingAttention(person.liveBills)
        // A week out, no further: see `Person.appointmentsDue`.
        let appointments = person.appointmentsDue()

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
                            complete(task)
                        }
                    }
                }
            }

            // Above the refill warning and below the errands, because an
            // appointment is the one thing on this screen that happens whether
            // or not anybody opens the app. It was previously nowhere: the app
            // could hold next Tuesday's cardiology appointment and never
            // mention it on the screen people open every morning.
            if !appointments.isEmpty {
                Section("Appointments") {
                    ForEach(appointments) { visit in
                        Button {
                            destination = .appointments
                        } label: {
                            AppointmentRow(visit: visit)
                        }
                        .buttonStyle(.plain)
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
                            pay(bill)
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
                // Blocked is told, not swallowed. Tapping this step and
                // watching it tick itself back off with no prompt and no
                // explanation is how the checklist taught people the app does
                // not work.
                switch await NotificationPermission.request() {
                case .granted:
                    break
                case .denied:
                    DoseReminderPreferences.setEnabled(false, personID: person.id)
                    setupVersion += 1
                case .blocked:
                    DoseReminderPreferences.setEnabled(false, personID: person.id)
                    setupVersion += 1
                    showNotificationsBlocked = true
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

        // Counts the day, not the tap. This is the app's core action, and
        // several days of it is the only honest evidence that Elderhub is
        // part of somebody's routine and therefore that asking them about it
        // is fair.
        ReviewPrompt.recordActiveDay()
        confirmations += 1

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

    /// Ticking a task off, with a way back.
    ///
    /// A task or a bill marked done on Today does not stay on screen the way a
    /// dose does: the section is built from what is still outstanding, so the
    /// row is simply gone the instant it is tapped. Doses were forgiving of a
    /// slip and these two were not, with nothing on screen saying so, and the
    /// only route back was to leave Today, find the right list, show completed
    /// rows and reopen it. At 6am, one-handed, that is not a recovery anybody
    /// makes; they just live with the wrong record.
    ///
    /// The follow-up occurrence a recurring task spawns is taken back too, and
    /// this is the one place that is right. `markIncomplete` deliberately
    /// leaves it, because reopening a task from the Tasks screen days later
    /// could delete a row the family has since edited or ticked off
    /// themselves. Here the row was created seconds ago by the very tap being
    /// undone and this device is holding the reference to it, so leaving it
    /// behind would mean an undo that quietly adds next month's errand.
    private func complete(_ task: CareTask) {
        let followUp = task.markComplete(by: CareTaskAuthor.name(from: groups), in: context)
        ReviewPrompt.recordActiveDay()
        let name = task.title.isEmpty ? "task" : task.title
        offerUndo("Marked \(name) done") {
            task.markIncomplete(in: context)
            followUp?.tombstone(in: context)
        }
    }

    private func pay(_ bill: Bill) {
        let followUp = bill.markPaid(by: CareTaskAuthor.name(from: groups), in: context)
        ReviewPrompt.recordActiveDay()
        let name = bill.payee.isEmpty ? "bill" : bill.payee
        offerUndo("Marked \(name) paid") {
            bill.markUnpaid(in: context)
            followUp?.tombstone(in: context)
        }
    }

    /// Replaces whatever was there: two banners stacked up is worse than
    /// losing the older undo, and the older row is still reachable on its own
    /// screen.
    private func offerUndo(_ message: String, perform: @escaping () -> Void) {
        confirmations += 1
        let action = UndoableAction(message: message, perform: perform)
        withAnimation(.snappy) { undo = action }
        Task {
            try? await Task.sleep(for: .seconds(7))
            guard undo?.id == action.id else { return }
            withAnimation(.snappy) { undo = nil }
        }
    }

    /// Asks what they think of Elderhub, but only on a day already dealt with.
    ///
    /// The gate that matters is `isClear` for everybody. This is a Medical-
    /// category app opened by people who are worried, and a card asking
    /// "is Elderhub helping?" in front of an overdue 8am dose is the app
    /// talking about itself while somebody is trying to find out whether their
    /// mother took her tablets. On a day where nothing is outstanding it is a
    /// fair question, and it is also the moment the app has just visibly done
    /// its job. Eleanor never sees it: the recipient's phone renders
    /// `CheckInHomeView` and never reaches this screen at all.
    private func considerAskingForReview() {
        guard !isAskingForReview else { return }
        let digests = TodayDigest.build(for: people, on: Date(), checkInState: checkInState)
        // A record with nothing in it is not a quiet day, it is an empty app.
        guard !digests.isEmpty, digests.allSatisfy(\.isClear),
              digests.contains(where: { !$0.hasNothingToShow }) else { return }
        guard ReviewPrompt.shouldAsk(isQuietDay: true) else { return }
        isAskingForReview = true
    }

    private func requestAppReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        AppStore.requestReview(in: scene)
    }

    private func openSupportMail() {
        guard let url = SupportMail.url(
            personCount: people.count,
            isSignedIn: auth.isSignedIn,
            lastSyncedAt: sync.lastSyncedAt
        ) else { return }
        openURL(url)
    }

    private func runningLowMedications(for person: Person) -> [Medication] {
        TodayDigest.runningLow(for: person)
    }

    /// Whose errand this is. Only meaningful once someone else is in the circle;
    /// alone, every task is the reader's and saying so on every row is noise.
    private func isMine(_ task: CareTask) -> Bool {
        guard groups.hasOtherMembers else { return false }
        return TaskPlanner.isAssigned(task, to: groups.selfUserID, named: groups.selfDisplayName)
    }
}

/// What was just ticked off, and the tap that puts it back.
struct UndoableAction: Identifiable {
    let id = UUID()
    let message: String
    let perform: () -> Void
}

/// A bar across the bottom of Today for a few seconds after something is
/// ticked off.
///
/// Deliberately a visible control rather than a swipe or a shake: the gesture
/// affordances this app already has are the ones people never find, and the
/// reader this is for is holding the phone in one hand with the other one busy.
private struct UndoBanner: View {
    let action: UndoableAction
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(action.message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                // The one control on the bar, and it is the reason the bar is
                // there, so it gets a real target rather than the height of its
                // own text.
                .frame(minWidth: 60, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("today.undo")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.secondary.opacity(0.2))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }
}

/// One upcoming appointment on the daily screen. Read-only: an appointment is
/// not something you tick off, and the row exists to answer "is there anything
/// this week", not to be edited from here.
private struct AppointmentRow: View {
    let visit: Visit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(whenLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var title: String { visit.displayTitle() }

    private var subtitle: String {
        // Never the same string twice: the specialty is the title when there is
        // no provider name, and repeating it underneath reads as a bug.
        let parts = [visit.specialty, visit.reason]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != title }
        return parts.joined(separator: " · ")
    }

    /// "Today", "Tomorrow", then the weekday. Inside a week nobody needs the
    /// date to work out how far away it is, which is the whole reason this row
    /// is on Today rather than only on the appointments screen.
    private var whenLabel: String {
        let calendar = Calendar.current
        let time = visit.timeLabel(calendar: calendar)

        let day: String
        if calendar.isDateInToday(visit.date) {
            day = "Today"
        } else if calendar.isDateInTomorrow(visit.date) {
            day = "Tomorrow"
        } else {
            day = visit.date.formatted(.dateTime.weekday(.abbreviated))
        }

        return time.isEmpty ? day : "\(day) \(time)"
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
                    // See `TodayTaskRow`: 44 points, matching the dose control.
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
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
                    // The same 44-point floor the dose button was given, and
                    // for the same reason: these three controls sit in one
                    // column on one screen, tapped one-handed, and only one of
                    // them had a hit area anybody had measured. A bare glyph is
                    // about 22 points.
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
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
                // A menu, not a label. Undo and Skip were reachable only by
                // swiping the row, which is invisible (nothing on screen says
                // the gesture exists) and is the hardest gesture for the older
                // hands this app is aimed at. The status was the obvious place
                // to tap to change the status, and it did nothing. The swipe
                // still works for anyone who knows it.
                Menu {
                    if status != .taken {
                        Button("Taken") { onRecord(.taken) }
                    }
                    if status != .skipped {
                        Button("Skipped") { onRecord(.skipped) }
                    }
                    Button("Not recorded yet") { onRecord(nil) }
                } label: {
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
                    // Colour is never the only signal: "Taken" is the word, and
                    // green is the reinforcement.
                    .frame(minWidth: 60, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("\(slot.medicationName) at \(timeLabel): \(status.label)")
                .accessibilityHint("Change what was recorded")
                .accessibilityIdentifier("today.dose.status")
            } else {
                Button("Taken") { onRecord(.taken) }
                    .buttonStyle(.borderedProminent)
                    // Was `.small`, which is roughly 28 points tall. This is
                    // the most-tapped control in the app, tapped one-handed,
                    // early, by people in their fifties and older, and it was
                    // the smallest thing on the screen. 44 is Apple's floor.
                    .controlSize(.regular)
                    .frame(minHeight: 44)
                    // Six doses gave six buttons all announced as "Taken", so
                    // VoiceOver could not tell a reader which drug they were
                    // about to record.
                    .accessibilityLabel("Mark \(slot.medicationName) at \(timeLabel) as taken")
                    // Set explicitly, because tests used to find this button by
                    // the identifier XCUITest derives from an unlabelled
                    // control's title. Giving it a real VoiceOver label changed
                    // that derived value and took the button out from under
                    // them. The identifier is for tests and the label is for
                    // people; leaving the two as the same string is what made
                    // an accessibility improvement look like a regression.
                    .accessibilityIdentifier("today.dose.take")
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

    private var timeLabel: String {
        slot.scheduledAt.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    TodayView()
        .modelContainer(SampleData.previewContainer())
        .environment(GroupService.shared)
        .environment(CheckInService.shared)
        .environment(DeviceModeService.shared)
        .environment(AuthService.shared)
        .environment(SyncCoordinator.shared)
        .environment(AppNavigator())
}
