import SwiftData
import SwiftUI

/// Decides which app this person gets.
///
/// The subject branch is a different root, not a disabled version of the same
/// one. Their reduced surface is enforced by RLS regardless (I4), so this is
/// about giving the person the app they were promised rather than a caregiver's
/// app with most of it greyed out.
struct RootView: View {
    // Tombstoned rows stay in the store until the outbox has pushed them, so
    // every list of people has to filter them out.
    @Query(filter: #Predicate<Person> { $0.deletedAt == nil }, sort: \Person.createdAt)
    private var people: [Person]

    @Environment(AuthService.self) private var auth
    @Environment(GroupService.self) private var groups
    @Environment(SyncCoordinator.self) private var sync
    @Environment(DeviceModeService.self) private var deviceMode
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("pendingInviteCode") private var pendingInviteCode = ""
    @State private var navigator = AppNavigator()
    @State private var authLinkError: String?
    @State private var onboardingSessionActive = false

    enum Tab: Hashable {
        case today, people, family, settings
    }

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingFlow(initialInviteCode: pendingInviteCode) {
                    pendingInviteCode = ""
                    hasCompletedOnboarding = true
                    onboardingSessionActive = false
                }
                .onAppear { onboardingSessionActive = true }
            } else if groups.requiresTransparency {
                TransparencyView(isOnboarding: true) {
                    Task { await sync.syncNow() }
                }
            } else if deviceMode.isRecipientMode {
                // Handed over on purpose, on this handset only. Same screen the
                // subject role gets, because it is the same person in the same
                // situation; the only difference is that this one has a way
                // back and that one does not.
                CheckInHomeView()
            } else if groups.role == .subject && groups.activeGroupID != nil {
                CheckInHomeView()
            } else {
                caregiverTabs
            }
        }
        .environment(navigator)
        .task {
            // Every read here is from the local cache and none of it touches the
            // network, so first paint never waits on a server (I1).
            auth.bootstrap()
            groups.loadFromCache()
            NotificationService.shared.start()

            await auth.refreshInBackground()
            await groups.refresh()
            await NotificationService.shared.registerIfAuthorized()
            await sync.syncNow()
            await DoseReminderScheduler.refresh(in: context)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await groups.refresh()
                await sync.syncNow()
                // Rescheduled every foreground so the 63-request window rolls
                // forward past whatever has already fired.
                await DoseReminderScheduler.refresh(in: context)
            }
        }
        .onOpenURL { url in
            if url.scheme == "elderhub", url.host == "auth" {
                Task { await finishEmailSignIn(url) }
                return
            }
            guard let code = InviteLink.code(from: url) else { return }
            pendingInviteCode = code
            if !people.isEmpty {
                navigator.showJoinInvite(code: code)
            }
        }
        .alert(
            "Email sign-in did not work",
            isPresented: Binding(
                get: { authLinkError != nil },
                set: { if !$0 { authLinkError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { authLinkError = nil }
        } message: {
            Text(authLinkError ?? "Request a new email link and try again.")
        }
    }

    /// An existing local-only install has people and a completed flag but no
    /// account. It must not be dragged back through onboarding: the med tracker
    /// it already has is the whole product for a solo caregiver (I3).
    private var needsOnboarding: Bool {
        if onboardingSessionActive { return true }
        return (!hasCompletedOnboarding || !pendingInviteCode.isEmpty) && people.isEmpty
    }

    private func finishEmailSignIn(_ url: URL) async {
        do {
            let name = UserDefaults.standard.string(forKey: "pendingEmailDisplayName") ?? ""
            try await auth.completeEmailSignIn(url: url, displayName: name)
            UserDefaults.standard.removeObject(forKey: "pendingEmailDisplayName")
            await StoreService.shared.identify()
            await NotificationService.shared.registerIfAuthorized()
            // Unlike the Apple button, this handler fires from anywhere, so the
            // sign-in is not always followed by a create-or-join step that would
            // load the circle. Someone signing in again on a new phone would
            // otherwise sit with no group until the next foreground.
            await groups.refresh()
            await sync.syncNow()
        } catch {
            authLinkError = error.localizedDescription
        }
    }

    private var caregiverTabs: some View {
        @Bindable var navigator = navigator
        return TabView(selection: $navigator.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "checklist") }
                .tag(Tab.today)

            PeopleView()
                .tabItem { Label("Care", systemImage: "person.2") }
                .tag(Tab.people)

            FamilyView()
                .tabItem { Label("Sharing", systemImage: "person.3") }
                .tag(Tab.family)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(SampleData.previewContainer())
        .environment(StoreService.shared)
        .environment(AuthService.shared)
        .environment(GroupService.shared)
        .environment(SyncCoordinator.shared)
        .environment(CheckInService.shared)
        .environment(DeviceModeService.shared)
}
