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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("pendingInviteCode") private var pendingInviteCode = ""
    @State private var navigator = AppNavigator()
    @State private var notificationRoute = NotificationRoute.shared
    @State private var authLinkError: String?
    @State private var onboardingSessionActive = false
    @State private var saveFailures = SaveFailureReporter.shared
    /// The container's width and fold, measured so the unfolded iPhone Duo can
    /// put the tabs and Care on opposite sides of the fold.
    @State private var paneGeometry = PaneGeometry(width: 0, fold: nil)

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
            // Not only a Sharing-screen concern. `loadMembers` is what applies
            // a narrowed access scope to the local mirror, and it used to be
            // reachable only from Sharing or Transparency: until somebody
            // wandered onto one of those screens, a phone whose access had been
            // withdrawn went on showing the records it had already downloaded,
            // readable offline. The server refusing new reads does not withdraw
            // the old ones, because a pull cursor cannot tell a removed row
            // from a row that simply did not change.
            await groups.loadMembers()
            await NotificationService.shared.registerIfAuthorized()
            await sync.syncNow()
            await DoseReminderScheduler.refresh(in: context)
        }
        .onChange(of: notificationRoute.pendingPersonID) { _, pending in
            // Tapping "Dad: Warfarin" has to land on Today whatever tab the app
            // was left on. Today itself consumes the id and switches person.
            guard pending != nil else { return }
            navigator.tab = .today
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await groups.refresh()
                await groups.loadMembers()
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
        .alert(
            "Not saved",
            isPresented: Binding(
                get: { saveFailures.message != nil },
                set: { if !$0 { saveFailures.message = nil } }
            )
        ) {
            Button("OK", role: .cancel) { saveFailures.message = nil }
        } message: {
            Text(saveFailures.message ?? "")
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

    /// Unfolded, Care has its own pane beside the tabs, so it is never a tab.
    private var split: UnfoldedSplit? {
        UnfoldedSplit.make(
            width: paneGeometry.width,
            isRegularWidth: horizontalSizeClass == .regular,
            fold: paneGeometry.fold
        )
    }

    /// One tree in every pose. Opening or closing the Duo moves frames, swaps
    /// the system tab bar for the strip at the top of the leading pane and
    /// drops the Care tab; Today, Sharing and Settings are never rebuilt, so
    /// they keep their scroll and pushed screens. Care is rebuilt where it
    /// moves, and reopens from `AppNavigator.carePath`.
    private var caregiverTabs: some View {
        @Bindable var navigator = navigator
        let split = split
        let chrome = PaneTabChrome(split: split)
        return ZStack(alignment: .topLeading) {
            // Shows only in the band under the fold, between the panes.
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            TabView(selection: $navigator.tab) {
                TodayView()
                    .systemTabBarHidden(!chrome.showsSystemTabBar)
                    .tabItem { Label("Today", systemImage: "checklist") }
                    .tag(Tab.today)

                if split == nil {
                    PeopleView()
                        .tabItem { Label("Care", systemImage: "person.2") }
                        .tag(Tab.people)
                }

                FamilyView()
                    .systemTabBarHidden(!chrome.showsSystemTabBar)
                    .tabItem { Label("Sharing", systemImage: "person.3") }
                    .tag(Tab.family)

                SettingsView()
                    .systemTabBarHidden(!chrome.showsSystemTabBar)
                    .tabItem { Label("Settings", systemImage: "gear") }
                    .tag(Tab.settings)
            }
            // iOS 27.1 lays a pane's bar row into the inner display's tall
            // status band. The strip takes that row in the leading pane, and
            // any top inset moves each tab's own bar down below the band.
            // Folded the inset is zero and the phone is unchanged.
            .safeAreaPadding(.top, chrome.contentInset)
            .overlay(alignment: .top) {
                PaneTabStrip(selection: $navigator.tab)
                    .padding(.top, PaneTabChrome.stripTop)
                    .ignoresSafeArea(.container, edges: .top)
                    .opacity(chrome.showsSystemTabBar ? 0 : 1)
                    .allowsHitTesting(!chrome.showsSystemTabBar)
                    .accessibilityHidden(chrome.showsSystemTabBar)
            }
            // The tabs stay inside the leading pane, never across the fold.
            .frame(maxWidth: split?.primaryWidth ?? .infinity, maxHeight: .infinity)

            if let split {
                PeopleView()
                    .frame(width: split.secondaryWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, split.secondaryX)
            }
        }
        // Each pane is phone-width, so its screens lay out as on a phone.
        .environment(\.horizontalSizeClass, split == nil ? horizontalSizeClass : .compact)
        .horizontalToolbarInPane(split != nil)
        .environment(\.isUnfoldedPane, split != nil)
        .onGeometryChange(for: PaneGeometry.self) { proxy in
            PaneGeometry(width: proxy.size.width, fold: proxy.verticalFold())
        } action: { paneGeometry = $0 }
        .onChange(of: split != nil) { _, isSplit in
            if isSplit, navigator.tab == .people { navigator.tab = .today }
        }
        .onChange(of: navigator.tab) { _, tab in
            // Care is already on screen beside whatever tab is showing.
            if tab == .people, split != nil { navigator.tab = .today }
        }
        #if DEBUG
        .onChange(of: paneGeometry) { _, geometry in
            guard DuoScreenshotTour.isEnabled else { return }
            NSLog("DUOGEOM width=%.1f fold=%@ split=%@", geometry.width,
                  String(describing: geometry.fold), String(describing: self.split))
        }
        .task(id: split != nil) { await runDuoTour(split: split != nil) }
        #endif
    }

    #if DEBUG
    private func runDuoTour(split: Bool) async {
        guard DuoScreenshotTour.isEnabled else { return }
        if let screen = DuoScreenshotTour.screen {
            // Late enough for the seeded people and the measured fold. The hub
            // goes first and its screen after, as a tap would: setting both in
            // one update pushed the screen mid-push and the pane drew it blank.
            // The wait also outlasts the inner display's first folded-size
            // layout: a folded route applied there and then handed to the new
            // Care pane lost the emergency card (review, 2026-10-23).
            let route = split ? screen : screen.folded
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            route.hub.apply(to: navigator, people: people)
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            route.apply(to: navigator, people: people)
            NSLog("DUOTOUR screen=%@ split=%@", screen.name, split ? "yes" : "no")
            return
        }
        let routes = DuoScreenshotTour.routes(split: split)
        guard !routes.isEmpty else { return }
        try? await Task.sleep(for: .seconds(DuoScreenshotTour.firstDelay))
        var index = 0
        while !Task.isCancelled {
            let route = routes[index % routes.count]
            route.apply(to: navigator, people: people)
            NSLog("DUOTOUR step=%d route=%@ split=%@", index, route.name, split ? "yes" : "no")
            index += 1
            try? await Task.sleep(for: .seconds(DuoScreenshotTour.step))
        }
    }
    #endif
}

/// The tabs while the Duo is split: a strip across the top of the leading
/// pane, where nothing scrolls under it (`PaneTabChrome`). Same tabs, names
/// and symbols as the system bar it replaces. Icon and title sit side by side
/// in a fixed-size icon slot, so every title shares one baseline.
private struct PaneTabStrip: View {
    @Binding var selection: RootView.Tab

    var body: some View {
        HStack(spacing: 2) {
            button(.today, title: "Today", symbol: "checklist")
            button(.family, title: "Sharing", symbol: "person.3")
            button(.settings, title: "Settings", symbol: "gear")
        }
        .padding(3)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .frame(height: PaneTabChrome.capsuleHeight)
        .padding(.horizontal, 16)
        // Fixed height, like the system bar, so its type is capped like one.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func button(_ tab: RootView.Tab, title: String, symbol: String) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            HStack(spacing: 6) {
                // Wide enough for the three-person symbol, so it never
                // touches its title.
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 20)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.accentColor.opacity(isSelected ? 0.12 : 0), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("pane-tab.\(title.lowercased())")
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
