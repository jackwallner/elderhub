import SwiftData
import SwiftUI

/// First launch, as a small explicit state machine.
///
/// The three-way fork at the top is the load-bearing part. Thirty apps in the
/// eldercare graveyard made the family group mandatory and none of them cleared
/// forty ratings. `.solo` exists so that a single caregiver who never invites
/// anyone still gets the entire medication tracker (invariant I3). If the group
/// ever becomes required, that finding has been rebuilt from scratch.
struct OnboardingFlow: View {
    enum Path: String, Identifiable {
        /// "Start a care record."
        case supporter
        /// "I have an invitation."
        case subject
        /// "Keep track of myself."
        case solo

        var id: String { rawValue }
    }

    enum Step: Equatable {
        case path
        case signIn
        case namePerson
        /// Everything else worth knowing, one skippable question at a time.
        case details
        case joinCode
        case transparency
        case joinedOverview
        case features
    }

    var initialInviteCode: String = ""
    let onFinished: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(GroupService.self) private var groups
    @Environment(SyncCoordinator.self) private var sync

    @State private var step: Step = .path
    @State private var path: Path = .supporter
    @State private var isWorking = false
    /// Guards the one non-idempotent thing in this flow: creating the circle.
    @State private var isAttachingGroup = false
    @State private var errorMessage: String?
    @State private var createdPersonName = ""
    @State private var createdPerson: Person?

    var body: some View {
        Group {
            switch step {
            case .path:
                PathPickerView { chosen in
                    path = chosen
                    step = firstStep(for: chosen)
                }

            case .signIn:
                SignInView(
                    purpose: signInPurpose,
                    onSignedIn: { handleSignedIn() },
                    // Joining a family is the one path that cannot proceed
                    // without an account: there is nothing to join without one.
                    onSkip: path == .subject ? nil : { step = .details }
                )

            case .namePerson:
                OnboardingView(
                    isSolo: path == .solo,
                    // Asked on the supporter path whether or not there is an
                    // account. It used to be gated on being signed in, which
                    // after the reorder would mean never, since this step now
                    // runs before the account does.
                    requiresAttestation: path == .supporter,
                    // Only ever the account holder's own name, and only on the
                    // path that asks for it. Apple already gave it to us.
                    suggestedName: path == .solo ? auth.displayName : ""
                ) { name, relationship, attested in
                    Task {
                        await createFirstPerson(
                            name: name,
                            relationship: relationship,
                            attested: attested
                        )
                    }
                }

            case .details:
                if let createdPerson {
                    OnboardingDetailsFlow(person: createdPerson) {
                        step = .features
                    }
                } else {
                    // Only reachable if the record vanished under us, which
                    // means there is nothing to ask questions about.
                    Color.clear.onAppear { step = .features }
                }

            case .joinCode:
                JoinGroupView(isOnboarding: true, initialCode: initialInviteCode) { role in
                    if role == .subject {
                        step = .transparency
                    } else {
                        step = .joinedOverview
                    }
                }

            case .transparency:
                TransparencyView(isOnboarding: true) {
                    finish()
                }

            case .joinedOverview:
                JoinedCareCircleView {
                    finish()
                }

            case .features:
                OnboardingFeatureOverview(personName: createdPersonName) {
                    finish()
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if canGoBack {
                Button {
                    goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.thinMaterial, in: Capsule())
                }
                .padding(.leading, 16)
                .padding(.top, 6)
                .accessibilityIdentifier("onboarding.back")
            }
        }
        .overlay {
            if isWorking {
                ProgressView().controlSize(.large)
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear { adoptInviteCode() }
        // A link tapped while this flow is already on screen changes the stored
        // code but never re-runs `onAppear`, so without this the tap does
        // nothing at all: the person is left on the fork they were already
        // looking at, holding a code the app has silently swallowed.
        .onChange(of: initialInviteCode) { _, _ in adoptInviteCode() }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn, step == .signIn else { return }
            handleSignedIn()
        }
    }

    /// The flow has no `NavigationStack` and nothing dismisses it, so without
    /// this two steps are one-way doors: `.signIn` on the subject path (where
    /// the skip button is deliberately absent, because there is nothing to join
    /// without an account) and `.joinCode`, which only ever moves forward.
    /// Someone who taps the wrong card, or who cannot get Apple sign-in to
    /// succeed, is stranded. A cold relaunch does land back on the fork, since
    /// `hasCompletedOnboarding` is still false, but "force quit the app" is not
    /// a recovery path to expect of this app's users.
    ///
    /// `.transparency` is excluded on purpose: it is reached only once the group
    /// has actually been joined, and there is nothing to go back to by then.
    private func adoptInviteCode() {
        guard !initialInviteCode.isEmpty else { return }
        auth.bootstrap()
        path = .subject
        step = auth.isSignedIn ? .joinCode : .signIn
    }

    private var canGoBack: Bool {
        switch step {
        case .signIn, .namePerson, .joinCode: return !isWorking
        // The details flow has its own Back and its own Skip on every step,
        // so a second floating Back over the top of them is one too many.
        case .path, .details, .transparency, .joinedOverview, .features: return false
        }
    }

    private var signInPurpose: SignInView.Purpose {
        switch path {
        case .supporter: return .createFamily
        case .subject: return .joinFamily
        case .solo: return .backUp
        }
    }

    /// Only the join path signs in first, because there is nothing to join
    /// without an account. Everywhere else the record is named first and the
    /// account is offered after it: that is what keeps a name field off the
    /// screen that follows Sign in with Apple (App Review 4.0, which rejected
    /// 1.0.1 for exactly that), and it puts the app's value before its wall.
    private func firstStep(for path: Path) -> Step {
        switch path {
        case .subject: return auth.isSignedIn ? .joinCode : .signIn
        case .supporter, .solo: return .namePerson
        }
    }

    /// `SignInView` reports a success twice: once from its completion handler
    /// and once from its own `isSignedIn` observer, and this view watches the
    /// same flag. Setting the step is idempotent; creating a circle is not,
    /// hence the flag inside `attachGroupAndContinue`.
    private func handleSignedIn() {
        guard step == .signIn else { return }
        switch path {
        case .subject:
            step = .joinCode
        case .supporter, .solo:
            Task { await attachGroupAndContinue() }
        }
    }

    /// Back out of the sign-in step takes the draft record with it, or walking
    /// forward again leaves two of them and picking a different path at the
    /// fork strands a half-named person in the Care tab. This is the one place
    /// `context.delete` is right rather than `tombstone()`: reaching this step
    /// means there is no account, so the row has never been pushed anywhere and
    /// holds nothing but the name just typed.
    private func goBack() {
        if step == .signIn, !auth.isSignedIn, let draft = createdPerson {
            context.delete(draft)
            try? context.save()
            createdPerson = nil
            createdPersonName = ""
        }
        step = .path
    }

    /// Creates the first recipient. The circle comes later, once there is an
    /// account to own it, and is still named after this person ("Mom's care
    /// circle") because they exist by then.
    private func createFirstPerson(name: String, relationship: String, attested: Bool) async {
        isWorking = true
        defer { isWorking = false }

        let isSelf = path == .solo || relationship.lowercased() == "me"

        // Reuse the draft when this step is answered a second time, so a Back
        // and a second run forward cannot leave two records behind.
        let person: Person
        if let draft = createdPerson {
            person = draft
            person.name = name
            person.relationship = relationship
            person.isSelf = isSelf
        } else {
            let existing = (try? context.fetchCount(FetchDescriptor<Person>())) ?? 0
            person = Person(
                name: name,
                relationship: relationship,
                colorIndex: existing,
                isSelf: isSelf
            )
            context.insert(person)
        }
        if attested, person.surrogateAttestedAt == nil { person.surrogateAttestedAt = Date() }
        try? context.save()

        createdPersonName = person.displayLabel
        createdPerson = person

        if auth.isSignedIn {
            await attachGroupAndContinue()
        } else {
            // No account means no group, and that is a complete, working app
            // (I3). The sign-in step that follows can be skipped outright.
            step = .signIn
        }
    }

    /// Creates the circle for a record that already exists, then adopts
    /// everything on the device into it.
    private func attachGroupAndContinue() async {
        guard !isAttachingGroup else { return }
        isAttachingGroup = true
        isWorking = true
        defer {
            isWorking = false
            isAttachingGroup = false
        }

        if auth.isSignedIn, let person = createdPerson {
            // Someone signing back in on a new phone already owns a circle, and
            // the cache this view was launched with predates that sign-in. Ask
            // before assuming there is none: the server refuses a second one.
            await groups.refresh()
            do {
                let groupID: UUID
                if let existing = groups.activeGroupID {
                    // Signing back into an account that already owns a circle:
                    // this record joins it rather than starting a second one,
                    // which the server would refuse anyway.
                    groupID = existing
                } else {
                    groupID = try await groups.createGroup(
                        named: groupName(for: person.name, isSelf: person.isSelf)
                    )
                }
                await sync.adoptLocalData(into: groupID)
            } catch {
                // The person is already saved locally and the app is fully
                // usable without the group, so this is reported and then
                // stepped past rather than trapping someone on an onboarding
                // screen with their data already entered.
                //
                // Said in full, though. The bare error message read as a
                // transient hiccup, and the next screen looked exactly like a
                // successful setup, so somebody could enter a fortnight of
                // medications believing their family could see them and find
                // out only when they went to send an invitation. Sharing → Start
                // a care circle is the retry; naming it is what turns an alert
                // into a recovery.
                errorMessage = """
                    \(error.localizedDescription)

                    \(person.displayLabel)'s record is saved on this phone and everything works, but the care circle was not created, so nothing is shared with your family yet. Open Sharing and tap "Start a care circle" to finish it.
                    """
            }
        }

        step = .details
    }

    private func groupName(for personName: String, isSelf: Bool) -> String {
        if isSelf { return "My care circle" }
        let trimmed = personName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Care circle" }
        return trimmed.hasSuffix("s") ? "\(trimmed)' care circle" : "\(trimmed)'s care circle"
    }

    private func finish() {
        Task { await sync.syncNow() }
        onFinished()
    }
}

// MARK: - The fork

struct PathPickerView: View {
    let onPick: (OnboardingFlow.Path) -> Void

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "list.clipboard")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)

                Text("Who are you here for?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                option(
                    title: "Start a care record",
                    detail: "For a parent, partner, or anyone you help.",
                    symbol: "figure.2.arms.open",
                    path: .supporter
                )
                option(
                    title: "I have an invitation",
                    detail: "Join a care circle from an email or code.",
                    symbol: "envelope.open",
                    path: .subject
                )
                option(
                    title: "Keep track of myself",
                    detail: "Make a private care record for yourself.",
                    symbol: "person",
                    path: .solo
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Text("You can change this later.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
    }

    private func option(
        title: String,
        detail: String,
        symbol: String,
        path: OnboardingFlow.Path
    ) -> some View {
        Button {
            onPick(path)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 34)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(title)
    }
}

private struct OnboardingFeatureOverview: View {
    let personName: String
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(personName)’s care record is ready")
                        .font(.title.bold())
                    Text("Start with what matters today. You do not need to set everything up at once.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    feature("pills", "Medications and doses", "Add schedules, then mark doses taken or skipped from Today.")
                    feature("cross.case", "Emergency card", "Keep allergies, conditions, contacts, providers, and medications available offline.")
                    feature("checklist", "Tasks, visits, readings, and notes", "Keep the practical details in one record instead of scattered messages.")
                    feature("person.3", "Share when you are ready", "Invite family by email. Invited helpers are free.")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Looking after more than one person?", systemImage: "person.2")
                        .font(.headline)
                    Text("Add Mom, Dad, or a partner under Care. Everyone you invite as a helper can see every person in this care circle.")
                        .foregroundStyle(.secondary)
                }

                Button("Open \(personName)’s record") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
                .accessibilityIdentifier("onboarding.open-record")
            }
            .padding(24)
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JoinedCareCircleView: View {
    @Environment(GroupService.self) private var groups
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "person.3.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text("You joined \(groups.groupName)")
                .font(.title.bold())
            Text("As a helper, you can see and update every person in this care circle. That includes medications, doses, health details, visits, readings, tasks, contacts, and notes.")
                .font(.body)
            Text("Elderhub keeps a copy on this phone, so the record remains available without a signal.")
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Open the care circle") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .padding(28)
    }
}

#Preview {
    PathPickerView { _ in }
}
