import SwiftData
import SwiftUI

/// One person's record, as a hub rather than a wall.
///
/// This screen used to be twelve identically-styled grey sections, and the
/// first thing a real user said about the app was that it was not clear what
/// features it had. That is a fair reading of what was on screen: "Visits",
/// "Providers", "Incidents & Symptoms" as grey rows tell someone who already
/// knows what they are that they exist, and tell everyone else nothing.
///
/// So the screen now says three things in order: who this is and what needs
/// doing (`PersonHeaderCard`), what is left to set up (`SetupProgressCard`),
/// and what the app can hold, each named *and explained* (`FeatureTile`). The
/// destinations are unchanged; only the way they announce themselves is.
///
/// Medications stay inline at the top rather than becoming a tile. This screen
/// is reached from a row that says "Eleanor's record", and the medication list
/// is the thing people came for; putting it behind one more tap to make the
/// grid tidier would be trading the product for the layout.
struct PersonDetailView: View {
    let person: Person

    @Environment(\.modelContext) private var context
    @Environment(GroupService.self) private var groups
    @Environment(CheckInService.self) private var checkIn
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isAddingMedication = false
    @State private var editingMedication: Medication?
    @State private var isEditingDetails = false
    @State private var remindersEnabled = false
    @State private var setupHidden = false
    @State private var dismissedSteps: Set<SetupStep.Kind> = []
    @State private var pushed: CareFeature?
    @State private var showEmergencyCard = false
    @State private var pendingDeletion: PendingRecordDeletion?

    /// The tiles, in the order a caregiver reaches for them. Check-in is last of
    /// the everyday group because it is set up once and then mostly read.
    private var everyday: [CareFeature] { [.tasks, .bills, .vitals, .incidents, .checkIn] }
    private var records: [CareFeature] { [.visits, .providers, .healthDetails, .contacts, .notes, .timeline] }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        List {
            Section {
                PersonHeaderCard(
                    person: person,
                    dosesTaken: dosesTaken,
                    dosesTotal: dosesTotal,
                    tasksDue: TaskPlanner.dueNow(person.liveTasks).count,
                    runningLow: runningLowCount
                )
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            .listRowSeparator(.hidden)

            if (setupHidden || !dismissedSteps.isEmpty) && !SetupChecklist.isFinished(setupSteps) {
                // The way back. Hiding the checklist, or waving away individual
                // rows, is meant to stop it nagging, not to destroy the only
                // guided path through setting a record up, and before this
                // there was no way to get it back short of reinstalling.
                Section {
                    Button("Show setup checklist") {
                        SetupCardPreferences.setHidden(false, personID: person.id)
                        SetupStepPreferences.restoreAll(personID: person.id)
                        setupHidden = false
                        dismissedSteps = []
                    }
                    .font(.body)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
            }

            if !setupHidden && !visibleSetupSteps.isEmpty {
                Section {
                    SetupProgressCard(
                        personLabel: person.displayLabel,
                        steps: visibleSetupSteps,
                        onSelect: perform,
                        onDismissStep: { step in
                            SetupStepPreferences.dismiss(step.kind, personID: person.id)
                            dismissedSteps.insert(step.kind)
                        },
                        onHide: {
                            SetupCardPreferences.setHidden(true, personID: person.id)
                            setupHidden = true
                        }
                    )
                    .accessibilityIdentifier("person-detail.setup-card")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
            }

            medicationsSection

            Section {
                Toggle("Dose reminders", isOn: $remindersEnabled)
                    .accessibilityIdentifier("person-detail.dose-reminders")
            } header: {
                Text("Reminders")
            } footer: {
                // Set per device on purpose: a sibling who wants no 8am ping
                // should not have to argue with whoever set the schedule.
                Text("Notifies this phone at each scheduled dose time for \(person.displayLabel). Reminders are set on each device separately.")
            }

            tileSection(
                title: "Every day",
                footer: "Everything here is kept on this phone first, so it opens with no signal.",
                features: everyday
            )

            tileSection(
                title: "Records",
                footer: nil,
                features: records
            )

            Section {
                // A `Button` rather than a `NavigationLink` for the same reason
                // the tiles are, plus one of its own: a link in a list row draws
                // the system disclosure chevron outside the card, next to the
                // one the banner already has.
                Button {
                    showEmergencyCard = true
                } label: {
                    EmergencyCardBanner(personLabel: person.displayLabel)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("person-detail.emergency-card")
            } header: {
                Text("For an ER visit")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 24, trailing: 0))
            .listRowSeparator(.hidden)
        }
        // Inline, and the short label: the header card already carries the full
        // name and the avatar, and a large title repeating it cost most of the
        // first screen on the one screen whose job is to show what is here.
        .navigationTitle(person.displayLabel)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pushed) { feature in
            destination(for: feature)
        }
        .navigationDestination(isPresented: $showEmergencyCard) {
            EmergencyCardView(person: person)
        }
        .sheet(isPresented: $isAddingMedication) {
            MedicationEditorSheet(person: person)
        }
        .sheet(item: $editingMedication) { medication in
            MedicationEditorSheet(person: person, medication: medication)
        }
        .sheet(isPresented: $isEditingDetails) {
            PersonDetailsEditorSheet(person: person)
        }
        .recordDeletionConfirmation($pendingDeletion)
        .onAppear {
            remindersEnabled = DoseReminderPreferences.isEnabled(personID: person.id)
            setupHidden = SetupCardPreferences.isHidden(personID: person.id)
            dismissedSteps = SetupStepPreferences.dismissed(personID: person.id)
        }
        .onChange(of: remindersEnabled) { _, enabled in
            setReminders(enabled)
        }
    }

    // MARK: - Sections

    private var medicationsSection: some View {
        Section {
            if person.activeMedications.isEmpty {
                // Says what the feature buys you, not just that it is empty.
                VStack(alignment: .leading, spacing: 4) {
                    Text("No medications yet")
                        .font(.body.weight(.medium))
                    Text("Add one to track doses, times and refills.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } else {
                ForEach(person.activeMedications) { med in
                    // Tappable, because the alternative was delete and retype:
                    // the one correction path a medication list cannot be
                    // missing is the one that fixes a wrong strength or time.
                    Button {
                        editingMedication = med
                    } label: {
                        MedicationRow(medication: med)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("person-detail.medication.\(med.id.uuidString)")
                }
                .onDelete(perform: requestMedicationDeletion)
            }

            Button {
                isAddingMedication = true
            } label: {
                Label("Add medication", systemImage: "plus")
            }
            .accessibilityIdentifier("person-detail.add-medication")
        } header: {
            Text("Medications")
        }
    }

    /// A grid of feature tiles inside a list section. The grid is one row, so
    /// the section header and footer still behave like every other section on
    /// the screen and nothing about list scrolling changes.
    private func tileSection(title: String, footer: String?, features: [CareFeature]) -> some View {
        Section {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(features) { feature in
                    tile(for: feature)
                }
            }
        } header: {
            Text(title)
                .padding(.leading, -4)
        } footer: {
            if let footer {
                Text(footer)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
        .listRowSeparator(.hidden)
    }

    /// Every tile is a `Button` driving one `navigationDestination`, not its own
    /// `NavigationLink`. Ten links inside a `LazyVGrid` inside a single `List`
    /// row look identical on screen and are not: the row swallows the tap and
    /// the push never happens, which the navigation UI test caught.
    ///
    /// Health details is the one feature whose editor is a sheet with its own
    /// navigation stack, so its tile presents rather than pushes.
    @ViewBuilder
    private func tile(for feature: CareFeature) -> some View {
        let label = FeatureTile(
            feature: feature,
            detail: detail(for: feature),
            isEmpty: CareOverview.isEmpty(feature, person: person)
        )

        Button {
            if feature == .healthDetails {
                isEditingDetails = true
            } else {
                pushed = feature
            }
        } label: {
            label
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier(for: feature))
    }

    /// Contacts keeps the identifier it shipped with rather than taking the
    /// feature's raw value, so the navigation UI test keeps testing the thing
    /// it was written to test instead of being edited to match a refactor.
    private func identifier(for feature: CareFeature) -> String {
        feature == .contacts
            ? "person-detail.emergency-contacts"
            : "person-detail.\(feature.rawValue)"
    }

    @ViewBuilder
    private func destination(for feature: CareFeature) -> some View {
        switch feature {
        case .medications, .healthDetails:
            // Medications are the list above; health details is a sheet.
            EmptyView()
        case .tasks:
            CareTasksView(person: person)
        case .vitals:
            VitalsView(person: person)
        case .visits:
            VisitsView(person: person)
        case .providers:
            ProvidersView(person: person)
        case .incidents:
            CareEventsView(person: person)
        case .timeline:
            TimelineView(person: person)
        case .notes:
            CareNotesView(person: person)
        case .bills:
            BillsView(person: person)
        case .contacts:
            EmergencyContactsView(person: person)
        case .checkIn:
            CheckInSettingsView(person: person)
        }
    }

    // MARK: - Tile copy

    /// The check-in tile is the one whose line depends on state rather than on
    /// a count, and it stays a statement of fact and never an assessment (I6).
    /// "Not checked in yet" is true; "Mom may need help" is a claim this app
    /// has no basis for and does not make.
    private func detail(for feature: CareFeature) -> String {
        guard feature == .checkIn else {
            return CareOverview.detail(for: feature, person: person)
        }
        guard let settings = checkIn.settings(for: person), settings.enabled else {
            return "Not set up"
        }
        return checkIn.hasCheckedInToday(person) ? "Checked in today" : "Not yet today"
    }

    // MARK: - Setup checklist

    private var visibleSetupSteps: [SetupStep] {
        let steps = SetupChecklist.visible(setupSteps, dismissed: dismissedSteps)
        return SetupChecklist.isFinished(steps) ? [] : steps
    }

    private var setupSteps: [SetupStep] {
        SetupChecklist.steps(
            for: person,
            remindersEnabled: remindersEnabled,
            hasSharedWithFamily: groups.hasSharedWithFamily,
            hasCheckIn: checkIn.settings(for: person)?.enabled == true
        )
    }

    /// Each step goes to the place the thing is actually done, so the checklist
    /// is a route into the app rather than a list of instructions.
    private func perform(_ step: SetupStep) {
        switch step.kind {
        case .addMedication:
            isAddingMedication = true
        case .doseReminders:
            remindersEnabled = true
        case .healthDetails:
            isEditingDetails = true
        case .emergencyContact:
            pushed = .contacts
        case .inviteFamily:
            // The invite lives on the Sharing tab, a peer of this screen's tab
            // that cannot be pushed onto this stack, so this switches tabs.
            navigator.showFamilyInvite()
        case .checkIn:
            pushed = .checkIn
        }
    }

    // MARK: - Numbers

    private var dosesTotal: Int {
        ScheduleEngine.slots(for: person, on: Date()).count
    }

    private var dosesTaken: Int {
        ScheduleEngine.slots(for: person, on: Date()).filter { $0.status == .taken }.count
    }

    private var runningLowCount: Int {
        person.activeMedications.filter { medication in
            guard let daysRemaining = medication.daysRemaining else { return false }
            return daysRemaining <= Double(medication.refillThresholdDays)
        }.count
    }

    // MARK: - Actions

    /// Permission is asked for here rather than at launch, because this is the
    /// first moment it buys the user anything.
    private func setReminders(_ enabled: Bool) {
        DoseReminderPreferences.setEnabled(enabled, personID: person.id)
        Task {
            let authorized = enabled ? await NotificationService.shared.isAuthorized() : true
            if enabled, !authorized {
                let granted = await NotificationService.shared.requestAuthorization()
                if !granted {
                    DoseReminderPreferences.setEnabled(false, personID: person.id)
                    remindersEnabled = false
                }
            }
            await DoseReminderScheduler.refresh(in: context)
        }
    }

    /// Asks first. A medication row is not a line of text: deleting it takes
    /// the dose history logged against it and, in a family group, takes it off
    /// every other phone too.
    private func requestMedicationDeletion(at offsets: IndexSet) {
        let meds = person.activeMedications
        let doomed = offsets.compactMap { meds.indices.contains($0) ? meds[$0] : nil }
        guard !doomed.isEmpty else { return }

        let name = doomed.count == 1 ? doomed[0].displayName : "\(doomed.count) medications"
        let doseCount = doomed.reduce(0) { $0 + $1.liveDoses.count }
        var detail = doomed.count == 1
            ? "\(name) comes off the list and off the emergency card."
            : "They come off the list and off the emergency card."
        if doseCount > 0 {
            detail += doseCount == 1
                ? " The 1 recorded dose goes with it."
                : " The \(doseCount) recorded doses go with it."
        }

        pendingDeletion = PendingRecordDeletion(
            title: doomed.count == 1 ? "Delete \(name)?" : "Delete \(doomed.count) medications?",
            message: PendingRecordDeletion.message(detail, isShared: groups.activeGroupID != nil),
            confirmLabel: "Delete",
            perform: { deleteMedications(doomed) }
        )
    }

    private func deleteMedications(_ meds: [Medication]) {
        for med in meds {
            med.tombstone(in: context)
        }
        try? context.save()
        Task { await DoseReminderScheduler.refresh(in: context) }
    }
}

private struct MedicationRow: View {
    let medication: Medication

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(medication.displayName)
                .font(.body.weight(.medium))

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if medication.isAsNeeded {
            parts.append("As needed")
        } else if !medication.scheduleMinutes.isEmpty {
            parts.append(
                medication.scheduleMinutes.sorted()
                    .map { ScheduleEngine.timeLabel(forMinutes: $0) }
                    .joined(separator: ", ")
            )
        }
        if !medication.purpose.isEmpty {
            parts.append(medication.purpose)
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        PersonDetailView(person: SampleData.previewPerson())
    }
    .modelContainer(SampleData.previewContainer())
    .environment(GroupService.shared)
    .environment(CheckInService.shared)
        .environment(DeviceModeService.shared)
    .environment(AppNavigator())
}
