import SwiftData
import SwiftUI

/// The subject's whole app, near enough.
///
/// One large button, their own medications underneath it, and a link to the page
/// that tells them who can see them. Nothing else. The person on this screen did
/// not choose to install this app and may be doing it with poor eyesight and
/// unsteady hands, so the button is deliberately enormous and the press is
/// confirmed by the screen changing rather than by a toast that disappears.
///
/// There is no paywall on this screen and no code path that could add one. The
/// press does not consult `StoreService` at any depth (I2).
struct CheckInHomeView: View {
    // Tombstoned rows stay in the store until the outbox has pushed them, so
    // every list of people has to filter them out.
    @Query(filter: #Predicate<Person> { $0.deletedAt == nil }, sort: \Person.createdAt)
    private var people: [Person]

    @Environment(AuthService.self) private var auth
    @Environment(GroupService.self) private var groups
    @Environment(SyncCoordinator.self) private var sync
    @Environment(CheckInService.self) private var checkIn

    @Environment(DeviceModeService.self) private var deviceMode

    @State private var justPressed = false
    @State private var showTransparency = false
    @State private var showEmergencyCard = false
    @State private var isUnlocking = false
    /// Held between the keypad accepting a code and the sheet finishing its
    /// dismissal animation. See the `onDismiss` below.
    @State private var acceptedPIN: String?

    /// Whose screen this is.
    ///
    /// Three sources, in this order, because they answer three different
    /// questions and only the first one is ever certain:
    ///
    /// 1. A handover names its person. Someone tapped their name a second ago,
    ///    so nothing here is a better answer than that.
    /// 2. Otherwise this is a subject's own account, and the row linked to
    ///    their user id is theirs by definition.
    /// 3. Otherwise guess, which is what the whole screen used to do.
    private var me: Person? {
        if deviceMode.isRecipientMode,
           let chosen = deviceMode.handedOverPersonID,
           let person = people.first(where: { $0.id == chosen }) {
            return person
        }
        if let userID = auth.userID,
           let linked = people.first(where: { $0.linkedUserID == userID }) {
            return linked
        }
        return people.first(where: \.isSelf) ?? people.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    if let person = me {
                        button(for: person)
                        status(for: person)
                        medications(for: person)

                        // Never behind the caregiver code, on purpose. The
                        // whole point of this page is the ten minutes when
                        // nobody can remember a passcode.
                        Button {
                            showEmergencyCard = true
                        } label: {
                            BigNavCard(
                                title: "Emergency card",
                                detail: "Allergies, conditions, medications and who to call. Works with no signal.",
                                symbol: "cross.case.fill",
                                tint: .red
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("check-in.emergency-card")
                    } else {
                        ContentUnavailableView(
                            "Nothing here yet",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("Your family's list has not reached this phone yet.")
                        )
                        .padding(.top, 60)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Today")
            .toolbar {
                // Only in handed-over mode. A subject whose *account* has the
                // subject role has nothing to unlock into: their reduced
                // surface is RLS, not a local preference (I4).
                if deviceMode.isRecipientMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if deviceMode.hasPIN {
                                isUnlocking = true
                            } else {
                                deviceMode.returnToCaregiver(pin: nil)
                            }
                        } label: {
                            Label("Caregiver", systemImage: deviceMode.hasPIN ? "lock.fill" : "lock.open")
                        }
                        .accessibilityIdentifier("check-in.unlock")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showTransparency = true
                    } label: {
                        Label("Who can see me", systemImage: "eye")
                    }
                }
            }
            .refreshable { await sync.syncNow() }
            .navigationDestination(isPresented: $showEmergencyCard) {
                if let person = me {
                    EmergencyCardView(person: person)
                }
            }
            .sheet(isPresented: $showTransparency) {
                NavigationStack {
                    TransparencyView(isOnboarding: false)
                }
            }
            // The swap happens on dismissal, not inside the keypad's callback.
            // Switching modes tears this screen down, and the sheet it is
            // presenting goes with it: accepting the code left the keypad on
            // screen over a root that had already changed underneath it, with
            // no way out. Verify, dismiss, then switch.
            .sheet(isPresented: $isUnlocking, onDismiss: {
                guard let acceptedPIN else { return }
                self.acceptedPIN = nil
                deviceMode.returnToCaregiver(pin: acceptedPIN)
            }) {
                CaregiverPINEntryView(purpose: .unlock) { pin in
                    guard deviceMode.verify(pin: pin) else { return false }
                    acceptedPIN = pin
                    return true
                }
            }
        }
    }

    // MARK: The button

    private func button(for person: Person) -> some View {
        let done = checkIn.hasCheckedInToday(person)

        return Button {
            guard !done else { return }
            checkIn.press(for: person, source: .selfPressed, by: auth.displayName)
            withAnimation(.spring(duration: 0.35)) { justPressed = true }
        } label: {
            VStack(spacing: 14) {
                Image(systemName: done ? "checkmark.circle.fill" : "hand.wave.fill")
                    .font(.system(size: 74, weight: .medium))
                Text(done ? "You checked in" : "I'm OK today")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .background(done ? Color.green : Color.accentColor, in: RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .disabled(done)
        .accessibilityLabel(done ? "You have checked in today" : "Check in, I'm OK today")
        .sensoryFeedback(.success, trigger: justPressed)
    }

    private func status(for person: Person) -> some View {
        VStack(spacing: 6) {
            if let last = checkIn.lastCheckIn(for: person) {
                Text("Last checked in \(last.pressedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                // Told honestly rather than hidden. A press that has not left
                // the phone yet is still a press, and pretending otherwise is
                // how people end up pressing it four times.
                if last.isDirty {
                    Label("Saved on this phone, will send when you have signal", systemImage: "arrow.up.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Press the button once a day so your family knows you're OK.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Their own medications

    @ViewBuilder
    private func medications(for person: Person) -> some View {
        let slots = ScheduleEngine.slots(for: person, on: Date())

        if !slots.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your medications today")
                    .font(.title3.bold())

                ForEach(slots) { slot in
                    SubjectDoseRow(slot: slot, person: person, name: auth.displayName)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A subject may log doses for their own linked recipient only (D32, §13 Q1).
/// Brief 01 argued they should not; overruled, because a parent capable of
/// pressing a proof-of-life button is capable of tapping "took my morning
/// pills", and the alternative is the family phoning to ask, which is the exact
/// chore this app exists to remove.
private struct SubjectDoseRow: View {
    let slot: DoseSlot
    let person: Person
    let name: String

    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(slot.medicationName)
                    .font(.title3.weight(.medium))
                Text(slot.scheduledAt.formatted(date: .omitted, time: .shortened))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let status = slot.status {
                Text(status.label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(status == .taken ? .green : .secondary)
            } else {
                Button("Taken") { record() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private func record() {
        guard let medication = person.liveMedications.first(where: { $0.id == slot.medicationID }) else { return }

        // Reuses a tombstoned row for the same slot rather than inserting
        // beside it. `DoseLog.id` is derived from (medication, scheduled
        // time), so a caregiver who undid this dose on their phone leaves a
        // tombstone here holding the id a new row would be given.
        let calendar = Calendar.current
        if let existing = medication.doses.first(where: {
            calendar.isDate($0.scheduledAt, equalTo: slot.scheduledAt, toGranularity: .minute)
        }) {
            existing.deletedAt = nil
            existing.status = .taken
            existing.recordedAt = Date()
            existing.recordedBy = name.isEmpty ? person.name : name
            existing.groupID = person.groupID
            existing.recordLocalChange(in: context)
            medication.decrementForDoseTaken()
            medication.recordLocalChange(in: context)
            return
        }

        let log = DoseLog(
            scheduledAt: slot.scheduledAt,
            status: .taken,
            recordedBy: name.isEmpty ? person.name : name,
            medication: medication
        )
        log.groupID = person.groupID
        context.insert(log)
        // Same rule as `TodayView`: a dose logged for the first time on this
        // device counts against what's on hand, a dose arriving through sync
        // does not.
        medication.decrementForDoseTaken()
        // The quantity lives on the medication, so the dose log alone does not
        // carry it to the rest of the family.
        medication.recordLocalChange(in: context)
        log.recordLocalChange(in: context)
        try? context.save()
    }
}
