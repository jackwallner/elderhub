import SwiftData
import SwiftUI
import UIKit
import UserNotifications

/// The caregiver side of the check-in: agreeing a window, and seeing whether it
/// was pressed.
///
/// "Agreed" is the operative word and the copy says so. This is a thing the
/// family and the person decided together, not a monitoring setting a child
/// switched on. That framing is also what keeps the feature the right side of
/// I6: it never claims to notice anything, it reports a button.
struct CheckInSettingsView: View {
    let person: Person

    @Environment(GroupService.self) private var groups
    @Environment(CheckInService.self) private var checkIn
    @Environment(AuthService.self) private var auth
    @Environment(\.modelContext) private var context

    private var notifications: NotificationService { .shared }

    @State private var enabled = false
    @State private var startMinute = 8 * 60
    @State private var endMinute = 20 * 60
    @State private var graceMinutes = 60
    @State private var didLoad = false

    private var canEdit: Bool { groups.role.isStaff }

    /// `.notDetermined` is not a failure: the prompt has simply not been
    /// answered yet, and `onChange` is about to raise it.
    private var notificationsDenied: Bool {
        switch notifications.authorizationStatus {
        case .denied: return true
        default: return false
        }
    }

    var body: some View {
        List {
            Section {
                Toggle("Daily check-in", isOn: $enabled)
                    .disabled(!canEdit)
            } footer: {
                Text("\(person.displayLabel) presses one button a day. If the button is not pressed by the end of the agreed window, everyone looking after them is told. Nobody is called and no help is sent.")
            }

            // The one thing this screen promises is that somebody gets told.
            // If this phone could not register for notifications, that promise
            // is not being kept, and saying nothing is the worst option.
            //
            // Denied permission is checked first, because it is both the
            // commoner cause and the one the user can fix. Before this, the
            // toggle read as on while iOS was dropping every notification, so
            // the whole feature looked set up and quietly was not.
            if enabled && notificationsDenied {
                Section {
                    Label("Notifications are off for Elderhub", systemImage: "bell.slash")
                        .foregroundStyle(.orange)
                    Text("Check-ins are still recorded, but this phone will not remind anyone and will not be told when one is missed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Open iOS Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            } else if enabled && notifications.remoteRegistrationFailed {
                Section {
                    Label("This phone can't receive alerts right now", systemImage: "bell.slash")
                        .foregroundStyle(.orange)
                    Text("Check-ins are still recorded, but this phone won't be told when one is missed. Check Notifications for Elderhub in iOS Settings, then reopen the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if enabled {
                Section {
                    timePicker("From", minute: $startMinute)
                    timePicker("Until", minute: $endMinute)
                    Picker("Wait a bit longer", selection: $graceMinutes) {
                        Text("No extra time").tag(0)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                } header: {
                    Text("The window you agreed")
                } footer: {
                    // The window is a pair of clock times inside one day, all
                    // the way down to a check constraint on the table and the
                    // escalation job's arithmetic. Saying so is the fix for
                    // what used to happen: entering 8 PM to 8 AM was accepted,
                    // then silently clamped to a one-minute window on the way
                    // out, and nothing on screen ever admitted it.
                    Text("The window has to start and end on the same day, so it cannot run through midnight. Moving one time pushes the other along to keep that true.")
                }
                .disabled(!canEdit)

                Section {
                    if let last = checkIn.lastCheckIn(for: person) {
                        LabeledContent("Last check-in") {
                            Text(last.pressedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        if last.source == .caregiverManual && !last.pressedByName.isEmpty {
                            Text("Recorded by \(last.pressedByName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No check-in recorded yet.")
                            .foregroundStyle(.secondary)
                    }

                    if canEdit && person.linkedUserID == nil {
                        // Dad has no phone. Someone has seen him; the record
                        // should say so, and say who said so.
                        Button("Record a check-in for \(person.displayLabel)") {
                            checkIn.press(
                                for: person,
                                source: .caregiverManual,
                                by: auth.displayName
                            )
                        }
                        .disabled(checkIn.hasCheckedInToday(person))
                    }
                }
            }
        }
        .navigationTitle("Check-in")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Re-read every time, not just on first load: the user may have
            // just come back from iOS Settings having changed it.
            await notifications.refreshStatus()
            guard !didLoad else { return }
            if let existing = checkIn.settings(for: person) {
                enabled = existing.enabled
                startMinute = existing.windowStartMinute
                endMinute = existing.windowEndMinute
                graceMinutes = existing.graceMinutes
            }
            didLoad = true
        }
        // The window is written on the way out, one sync rather than one per
        // tick of a time picker. The toggle is written the instant it moves:
        // it is the whole feature, and leaving the only record of it in view
        // state until the screen happens to be dismissed is how "I turned it
        // on" becomes "it was never on".
        .onDisappear { save() }
        // Corrected while the pickers are still on screen, so the user sees the
        // adjustment happen and can argue with it. Doing it in `save()` meant
        // the value they chose and the value that was stored differed with no
        // moment at which the two were both visible.
        .onChange(of: startMinute) { _, newValue in
            guard didLoad, endMinute <= newValue else { return }
            endMinute = min(24 * 60 - 1, newValue + 60)
        }
        .onChange(of: endMinute) { _, newValue in
            guard didLoad, newValue <= startMinute else { return }
            startMinute = max(0, newValue - 60)
        }
        .onChange(of: enabled) { _, newValue in
            // Compared against what is stored rather than against a "did I
            // load yet" flag. `onChange` also fires for the load's own
            // assignment, and that is not the user touching anything: it must
            // not write the settings straight back or re-raise the permission
            // prompt every time the screen is opened.
            let stored = checkIn.settings(for: person)?.enabled ?? false
            guard stored != newValue else { return }
            save()
            guard newValue else { return }
            Task { await NotificationService.shared.requestAuthorization() }
        }
    }

    private func timePicker(_ label: String, minute: Binding<Int>) -> some View {
        DatePicker(
            label,
            selection: Binding(
                get: {
                    Calendar.current.date(
                        bySettingHour: minute.wrappedValue / 60,
                        minute: minute.wrappedValue % 60,
                        second: 0,
                        of: Date()
                    ) ?? Date()
                },
                set: { minute.wrappedValue = ScheduleEngine.minutes(from: $0) }
            ),
            displayedComponents: .hourAndMinute
        )
    }

    private func save() {
        guard canEdit else { return }
        // Stored as minutes from midnight plus an IANA zone, matching
        // `Medication.scheduleMinutes`, so the window survives travel and DST
        // rather than drifting the way a stored absolute time would.
        // The pickers keep the pair ordered, so this is a backstop against the
        // table's check constraint rather than the place the rule is enforced.
        checkIn.upsertSettings(
            for: person,
            enabled: enabled,
            startMinute: startMinute,
            endMinute: max(endMinute, startMinute + 1),
            graceMinutes: graceMinutes
        )
    }
}
