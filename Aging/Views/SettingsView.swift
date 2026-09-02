import SwiftData
import SwiftUI

struct SettingsView: View {
    // Tombstoned rows stay in the store until the outbox has pushed them, so
    // every list of people has to filter them out.
    @Query(filter: #Predicate<Person> { $0.deletedAt == nil }, sort: \Person.createdAt)
    private var people: [Person]

    @Environment(StoreService.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(GroupService.self) private var groups
    @Environment(SyncCoordinator.self) private var sync
    @Environment(DeviceModeService.self) private var deviceMode
    @Environment(\.openURL) private var openURL

    @State private var showPaywall = false
    @State private var isDeletingAccount = false
    @State private var isRestoring = false
    @State private var restoreResult: String?
    @State private var setupPerson: Person?
    @State private var isSettingPIN = false
    @State private var isConfirmingHandover = false
    @State private var isAskingForReview = false

    private var isUnlocked: Bool { store.isPro || groups.hasPlus }

    /// Restore has to say something. Swallowed with `try?`, a failed restore
    /// and a restore that found no purchase and a restore that worked all
    /// looked identical: nothing happened. Someone who has paid and cannot get
    /// their purchase back needs to know which of the three it was.
    private func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await store.restore()
            restoreResult = isUnlocked
                ? "Your purchase is back. Everything is unlocked."
                : "No previous purchase was found on this Apple ID."
        } catch {
            restoreResult = "Couldn't reach the App Store. \(error.localizedDescription)"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !isUnlocked {
                    Section {
                        Button {
                            showPaywall = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Upgrade to Elderhub Plus")
                                    .font(.headline)
                                Text("Add more people to this care circle. Every feature is already free for the first person.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text("One person pays. Invited family members are never separate seats.")
                    }
                } else if groups.hasPlus && !store.isPro {
                    Section {
                        Label("Elderhub Plus, through your care circle", systemImage: "checkmark.seal")
                    } footer: {
                        Text("Someone else in your family is paying for this.")
                    }
                }

                whoUsesThisPhoneSection
                setupSection
                syncSection
                privacySection

                feedbackSection

                Section {
                    Button("Restore purchases") {
                        Task { await restore() }
                    }
                    .disabled(isRestoring)
                    if auth.isSignedIn {
                        Button("Sign out") {
                            Task { await auth.signOut() }
                        }
                        Button("Delete my account", role: .destructive) {
                            isDeletingAccount = true
                        }
                    }
                }

                Section {
                    // Medical category, App Review 1.4.1. This app must never
                    // claim to treat, cure or diagnose. This paragraph and the
                    // one on the emergency card both stay.
                    Text("This app helps you organize medication and health information. It is not a medical device and does not provide medical advice. It cannot tell whether anyone is unwell and it does not call for help. Always follow the guidance of a licensed clinician.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $isDeletingAccount) {
                DeleteAccountSheet()
            }
            .sheet(item: $setupPerson) { person in
                NavigationStack {
                    OnboardingDetailsFlow(person: person) {
                        // Waving a row away and then re-running setup is a
                        // contradiction, so the run puts the checklist back.
                        SetupCardPreferences.setHidden(false, personID: person.id)
                        SetupStepPreferences.restoreAll(personID: person.id)
                        setupPerson = nil
                    }
                    .navigationTitle("Set Up \(person.displayLabel)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { setupPerson = nil }
                        }
                    }
                }
            }
            .sheet(isPresented: $isSettingPIN) {
                SetCaregiverPINSheet()
            }
            .sheet(isPresented: $isAskingForReview) {
                ReviewPromptSheet { outcome in
                    switch outcome {
                    case .notNow:
                        ReviewPrompt.markAsked()
                    case .wantsToRate:
                        ReviewPrompt.markSettled()
                        openURL(AppStoreReviewLinks.writeReviewURL)
                    case .sendingFeedback:
                        ReviewPrompt.markSettled()
                        openSupportMail()
                    }
                }
            }
            .confirmationDialog(
                handoverCandidates.count > 1 ? "Who is holding the phone?" : "Hand this phone over?",
                isPresented: $isConfirmingHandover,
                titleVisibility: .visible
            ) {
                // Asked, never inferred. With two parents on one handset the
                // check-in screen has no way to know which of them was handed
                // it, and guessing shows one of them the other's medications.
                if handoverCandidates.count > 1 {
                    ForEach(handoverCandidates) { person in
                        Button(person.displayLabel) { deviceMode.handOver(to: person.id) }
                            .accessibilityIdentifier("settings.hand-over.\(person.id.uuidString)")
                    }
                } else {
                    Button("Switch to their view") {
                        deviceMode.handOver(to: handoverCandidates.first?.id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    deviceMode.hasPIN
                    ? "The app switches to one big check-in button, their medications and the emergency card. Your code brings it back."
                    : "The app switches to one big check-in button, their medications and the emergency card. You have not set a code, so anyone can switch it back."
                )
            }
            // The generic "Something went wrong" alert that used to sit here
            // was never presented: nothing on this screen ever set its message.
            // `DeleteAccountSheet` reports its own errors inline.
            .alert(
                "Restore purchases",
                isPresented: Binding(get: { restoreResult != nil }, set: { if !$0 { restoreResult = nil } })
            ) {
                Button("OK", role: .cancel) { restoreResult = nil }
            } message: {
                Text(restoreResult ?? "")
            }
        }
    }

    /// Which side of the app this handset is on, said out loud.
    ///
    /// Two different things get confused here and the copy has to keep them
    /// apart. The *account's* role in the care circle is an agreement between
    /// people, enforced on the server, and only the organizer can change it;
    /// that is the line under "In this care circle". Who is holding *this
    /// phone* is a local fact that changes several times a day, and that is the
    /// switch. Before this, neither was visible anywhere outside the Sharing
    /// tab, so the app never actually said which one you were.
    @ViewBuilder
    private var whoUsesThisPhoneSection: some View {
        Section {
            LabeledContent("This phone") {
                Text(deviceMode.mode.label)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("These records") {
                Text(recordOwnership)
                    .multilineTextAlignment(.trailing)
            }

            if groups.activeGroupID != nil {
                LabeledContent("In this care circle") {
                    Text(groups.role.label)
                }
            }

            Button {
                isConfirmingHandover = true
            } label: {
                Label("Hand the phone to them", systemImage: "hand.wave")
            }
            .accessibilityIdentifier("settings.hand-over")

            Button {
                isSettingPIN = true
            } label: {
                Label(
                    deviceMode.hasPIN ? "Change the caregiver code" : "Set a caregiver code",
                    systemImage: deviceMode.hasPIN ? "lock.fill" : "lock.open"
                )
            }
            .accessibilityIdentifier("settings.caregiver-code")
        } header: {
            Text("Who uses this phone")
        } footer: {
            Text(
                groups.activeGroupID != nil
                ? "Handing over swaps this phone to their view: a check-in button, their medications and the emergency card, with nothing editable. Your circle role is set by the organizer on the Sharing tab and is separate from this."
                : "Handing over swaps this phone to their view: a check-in button, their medications and the emergency card, with nothing editable. The emergency card is never behind the code."
            )
        }
    }

    /// Who the phone can be handed to.
    ///
    /// The user's own record is not a candidate: recipient mode is what you
    /// switch to when you give the handset to somebody else, and "hand the
    /// phone to me" is not a thing anyone does. A store holding nothing but
    /// the user's own record falls back to it rather than leaving the button
    /// with no answer at all.
    private var handoverCandidates: [Person] {
        let others = people.filter { !$0.isSelf }
        return others.isEmpty ? people : others
    }

    /// Whether these records are the user's own or somebody else's, which is
    /// chosen on the very first screen of the app and was then never shown or
    /// changeable again. Each record's own toggle lives in its details editor.
    private var recordOwnership: String {
        let mine = people.filter(\.isSelf)
        let others = people.filter { !$0.isSelf }

        switch (mine.count, others.count) {
        case (0, 0): return "None yet"
        case (_, 0): return "Your own"
        case (0, 1): return "Kept for \(others[0].displayLabel)"
        case (0, _): return "Kept for \(others.count) people"
        default: return "Yours, and \(others.count == 1 ? others[0].displayLabel : "\(others.count) others")"
        }
    }

    /// Setting up again, without deleting anything.
    ///
    /// The checklist could be dismissed row by row and hidden as a card, and
    /// the only route back was a button buried on the person's own hub. Anyone
    /// who tidied it away and later wanted the questions again had nowhere
    /// obvious to look, and Settings is where people look.
    @ViewBuilder
    private var setupSection: some View {
        if !people.isEmpty {
            Section {
                ForEach(people) { person in
                    Button {
                        setupPerson = person
                    } label: {
                        Label("Set up \(person.displayLabel) again", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("settings.rerun-setup.\(person.id.uuidString)")
                }
            } header: {
                Text("Setup")
            } footer: {
                Text("Walks through date of birth, allergies, conditions, contacts, medications, doctors and reminders again. Nothing is deleted, every step can be skipped, and the checklist on Today comes back.")
            }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        Section {
            if auth.isSignedIn {
                LabeledContent("Signed in as") {
                    Text(auth.displayName.isEmpty ? "Your Apple account" : auth.displayName)
                }
                if let lastSyncedAt = sync.lastSyncedAt {
                    LabeledContent("Last synced") {
                        Text(lastSyncedAt.formatted(date: .omitted, time: .shortened))
                    }
                } else {
                    // Told plainly rather than hidden. A pending write is not a
                    // lost one, and saying so is what stops people re-entering
                    // everything.
                    Text("Not synced yet. Your list is safe on this phone.")
                        .foregroundStyle(.secondary)
                }
                if auth.isOffline || sync.isOffline {
                    Label("Showing your saved copy", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                } else if let lastError = sync.lastError {
                    // Said out loud, because the alternative is what shipped:
                    // a "last synced" line that kept advancing while nothing
                    // left the phone. Reported here and nowhere else, so it
                    // never sits in front of reading the medication list (I1).
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Couldn't sync", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)
                        Text("Your changes are saved on this phone and will be sent when this clears. \(lastError)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if sync.conflictCount > 0 {
                    // A destination, not a label. This counted flagged records
                    // for two builds while offering no way to reach one, which
                    // is a worry with nothing to do about it.
                    NavigationLink {
                        ConflictsView()
                    } label: {
                        Label(
                            "\(sync.conflictCount) change\(sync.conflictCount == 1 ? "" : "s") need a look",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                }
                Button("Sync now") {
                    Task { await sync.syncNow() }
                }
                .disabled(sync.isSyncing)
            } else {
                // A statement with nothing to do about it was the whole of this
                // branch, and Settings is where people look for a backup. The
                // only sign-in in the app lived behind the **Sharing** tab, so
                // a solo caregiver with no siblings had no reason ever to open
                // the one screen that offered it, and kept a parent's entire
                // medical record on a single phone with no copy of it
                // anywhere. Sharing is not the point being made here; not
                // losing the list is.
                Text("Everything is saved on this phone, and nowhere else. If you lose the phone, the record goes with it.")
                    .foregroundStyle(.secondary)
                NavigationLink {
                    BackUpSignInView()
                } label: {
                    Label("Sign in to back this up", systemImage: "icloud.and.arrow.up")
                }
                .accessibilityIdentifier("settings.sign-in")
            }
        } header: {
            Text("Account")
        } footer: {
            if !auth.isSignedIn {
                Text("Signing in backs up the record and lets you bring it back on a new phone. It adds nobody to it: sharing with family is a separate step on the Sharing tab.")
            }
        }
    }

    /// Rating and feedback, said plainly and reachable on purpose.
    ///
    /// The app had neither: no rating request anywhere, and support was a link
    /// to a web page. In a category whose whole shelf is decided by rating
    /// count, that is not a missing nicety. A deliberate tap here is never
    /// gated by the passive prompt's eligibility rules: somebody who came
    /// looking for this has already decided.
    private var feedbackSection: some View {
        Section {
            Button {
                isAskingForReview = true
            } label: {
                Label("Rate Elderhub", systemImage: "star")
            }
            .accessibilityIdentifier("settings.rate")

            Button {
                openSupportMail()
            } label: {
                Label("Email us about a problem", systemImage: "envelope")
            }
            .accessibilityIdentifier("settings.contact")
        } header: {
            Text("Feedback")
        } footer: {
            Text("The email arrives with your app version and whether sync is working, and nothing at all from the care record.")
        }
    }

    private func openSupportMail() {
        guard let url = SupportMail.url(
            personCount: people.count,
            isSignedIn: auth.isSignedIn,
            lastSyncedAt: sync.lastSyncedAt
        ) else { return }
        openURL(url)
    }

    private var privacySection: some View {
        Section {
            Label("A full copy lives on this phone, so it opens with no signal", systemImage: "iphone")
            Label("No location, ever. This app never asks for it", systemImage: "location.slash")
            Label("Nothing is used for advertising or tracking", systemImage: "hand.raised")
            Link(destination: URL(string: "https://jackwallner.github.io/elderhub/privacy-policy.html")!) {
                Label("Privacy policy", systemImage: "doc.text")
            }
            Link(destination: URL(string: "https://jackwallner.github.io/elderhub/terms.html")!) {
                Label("Terms of use", systemImage: "doc.plaintext")
            }
            Link(destination: URL(string: "https://jackwallner.github.io/elderhub/support.html")!) {
                Label("Support", systemImage: "questionmark.circle")
            }
        } header: {
            Text("Privacy")
        }
    }
}

/// Sign in reached from Settings rather than from onboarding or Sharing.
///
/// It pops itself once the account exists, so the reader lands back on the
/// Account section and sees "Signed in as" and a sync time, which is the
/// confirmation they came for. Left pushed, the same screen just sits there
/// still saying "Keep your list safe" with no sign it worked.
private struct BackUpSignInView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SignInView(purpose: .backUp) { dismiss() }
            .navigationTitle("Back Up")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// App Review 5.1.1(v). The RPC hands off or cleans up any group this account
/// owns and unlinks it from any recipient row, but never deletes the family's
/// medical history (I5): rows this person authored keep a name snapshot, so the
/// record still reads "logged by Sarah" after Sarah is gone.
private struct DeleteAccountSheet: View {
    @Environment(AuthService.self) private var auth
    @Environment(GroupService.self) private var groups
    @Environment(\.dismiss) private var dismiss

    @State private var typed = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let phrase = "DELETE"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Your account is removed and this phone is signed out.")
                    Text("What your family built together stays with them. Anything you entered keeps your name on it, so their record still makes sense.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Type \(phrase)", text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Delete my account", role: .destructive) {
                        Task { await delete() }
                    }
                    .disabled(typed.uppercased() != phrase || isWorking)
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func delete() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.deleteAccount()
            groups.forgetGroupLocally()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(SampleData.previewContainer())
        .environment(StoreService.shared)
        .environment(AuthService.shared)
        .environment(GroupService.shared)
        .environment(SyncCoordinator.shared)
        .environment(DeviceModeService.shared)
}
