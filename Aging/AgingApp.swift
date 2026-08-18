import SwiftData
import SwiftUI

@main
struct AgingApp: App {
    /// APNs hands the device token to the app delegate and nowhere else.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var store = StoreService.shared
    @State private var auth = AuthService.shared
    @State private var groups = GroupService.shared
    @State private var sync = SyncCoordinator.shared
    @State private var checkIn = CheckInService.shared
    @State private var deviceMode = DeviceModeService.shared

    init() {
        #if DEBUG
        // UI tests need a known starting state; the store is otherwise persistent
        // across launches by design.
        if Self.launchFlag("uitest-reset") {
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
            // A code left behind by an earlier run sends the flow straight into
            // the subject/join branch, so "fresh onboarding" tests never see
            // the path picker and fail on a shared simulator for a reason that
            // has nothing to do with what they are testing. The pool devices
            // are reused across sessions, so this has to be cleared here.
            UserDefaults.standard.removeObject(forKey: "pendingInviteCode")
            // Handing the phone over is persisted, and nothing else in a test
            // run clears it. A bundle that leaves the device in recipient mode
            // launches every later test onto the check-in screen, where none of
            // their elements exist, so one failure would cascade into a dozen
            // for a reason unrelated to any of them.
            DeviceModeService.shared.clearPIN()
        }

        // Stronger than `uitest-reset`, and separate from it on purpose: that
        // flag clears onboarding only, and several tests depend on the store
        // surviving. This one drops the store file, which is what a render test
        // seeded with `SampleData` needs. `seedIfEmpty` does nothing on a
        // simulator that already holds last week's demo data, so without this a
        // newly seeded feature is simply absent and the screenshot is of the
        // old app. Must run before anything touches `sharedModelContainer`.
        if Self.launchFlag("uitest-wipe-store") {
            CareModelStore.wipeStoreFilesForTesting()
        }

        // Puts a second person in the care circle, which is what the tasks
        // screen's Everyone/Mine filter is gated on. Separate from `seedDemo`
        // because it seeds no records at all, only the membership cache, and
        // the flow it is used by types its own tasks in.
        if Self.launchFlag("uitest-family") {
            SampleData.seedDemoCircle(into: CareModelStore.sharedModelContainer.mainContext)
        }

        // Store screenshots. `SampleData` already builds two years of history
        // for previews, so the shots show a real list rather than the empty
        // state, and nothing has to be typed in by hand on a headless sim.
        // Launch with: `simctl launch <udid> com.jackwallner.aging -seedDemo YES`
        if Self.launchFlag("seedDemo") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            SampleData.seedIfEmpty(into: CareModelStore.sharedModelContainer.mainContext)
        }
        #endif
    }

    #if DEBUG
    /// `NSArgumentDomain` strips the leading dash, so a launch argument passed
    /// as `-seedDemo YES` lands under `seedDemo`. Both spellings are read
    /// because the dashed one is what every call site here used to ask for,
    /// and asking for the wrong one fails silently: the flag is simply never
    /// seen and the app carries on with whatever state it already had.
    private static func launchFlag(_ name: String) -> Bool {
        UserDefaults.standard.bool(forKey: name) || UserDefaults.standard.bool(forKey: "-\(name)")
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(auth)
                .environment(groups)
                .environment(sync)
                .environment(checkIn)
                .environment(deviceMode)
                .onAppear { store.start() }
        }
        .modelContainer(CareModelStore.sharedModelContainer)
    }
}
