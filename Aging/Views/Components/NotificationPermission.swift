import SwiftUI
import UIKit
import UserNotifications

/// Turning a reminder on, and saying so when iOS refuses.
///
/// Every reminder toggle in the app used to do the same thing on a refusal:
/// flip the preference back off and say nothing. That is silent in the worst
/// possible way, because `requestAuthorization` returns false *without showing
/// a prompt* once notifications have been denied for the app, which is the
/// common case rather than the rare one. Someone who declined the system alert
/// during onboarding, or on another screen weeks ago, taps "Dose reminders",
/// watches the switch slide back, and concludes the app is broken. There is no
/// prompt to answer and no hint that the answer lives in iOS Settings.
///
/// This is the one place that decides what happens, so the three toggles cannot
/// drift apart again. It never flips the preference back on by itself: the
/// switch is off because the reminder genuinely will not fire, and pretending
/// otherwise is the failure this app is most careful about elsewhere (a
/// caregiver who believes a reminder is set when it is not is worse off than
/// one who knows).
@MainActor
enum NotificationPermission {
    /// What the caller should do with the toggle it just moved.
    enum Outcome {
        /// Permission is in place. Leave the toggle on.
        case granted
        /// iOS asked and the user said no, just now. Put the toggle back.
        case denied
        /// Refused without asking, because notifications are already off for
        /// Elderhub in iOS Settings. Put the toggle back *and* explain, because
        /// this is the case with no system prompt attached to it.
        case blocked
    }

    /// Asks only when asking can produce a prompt, and reports which of the
    /// three things happened.
    static func request() async -> Outcome {
        let service = NotificationService.shared
        if await service.isAuthorized() { return .granted }

        // `.denied` means the app has already been refused and iOS will not ask
        // again. Requesting here returns false instantly and shows nothing, so
        // it has to be told apart from a fresh refusal.
        if service.authorizationStatus == .denied { return .blocked }

        return await service.requestAuthorization() ? .granted : .denied
    }

    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension View {
    /// The alert shown for `Outcome.blocked`: what happened, and the one tap
    /// that fixes it.
    func notificationsBlockedAlert(isPresented: Binding<Bool>) -> some View {
        alert("Reminders are off for Elderhub", isPresented: isPresented) {
            Button("Open Settings") { NotificationPermission.openSettings() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("iOS is blocking notifications for this app, so reminders can't be delivered. Turn on Notifications for Elderhub in Settings, then switch reminders back on here.")
        }
    }
}
