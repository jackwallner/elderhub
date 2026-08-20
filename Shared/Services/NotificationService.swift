import Foundation
import OSLog
import UIKit
import UserNotifications

/// Notification permission, the APNs token, and nothing else.
///
/// The token is stored on `profiles.apns_token` and read only by the escalation
/// function running as the service role. No client can read another member's
/// token; `pending_notices_with_targets()` is revoked from `authenticated`
/// precisely so that a caregiver cannot enumerate the family's devices.
@MainActor
@Observable
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Set when APNs refuses to issue a token. Observable rather than only an
    /// OSLog line, because the failure is otherwise perfectly silent: someone
    /// turns on check-in reminders, is told nothing, and simply never hears
    /// about a missed check-in. The commonest cause is a build with no
    /// `aps-environment` entitlement, where this fails every single time.
    private(set) var remoteRegistrationFailed = false

    private let log = Logger(subsystem: "com.jackwallner.aging", category: "push")

    private override init() {
        super.init()
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current()
            .notificationSettings()
            .authorizationStatus
    }

    func isAuthorized() async -> Bool {
        await refreshStatus()
        return authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    /// Asked for at the moment it means something (turning check-in on, or
    /// joining a family), never on first launch where it reads as noise and gets
    /// refused permanently.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            return granted
        } catch {
            log.error("Authorization request failed: \(error.localizedDescription)")
            return false
        }
    }

    func registerIfAuthorized() async {
        guard await isAuthorized() else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func noteRemoteRegistrationFailed() { remoteRegistrationFailed = true }

    func store(deviceToken: Data) async {
        remoteRegistrationFailed = false
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard let userID = AuthService.shared.userID else { return }
        do {
            try await AuthService.shared.client
                .from("profiles")
                .update(["apns_token": token])
                .eq("id", value: userID)
                .execute()
            log.info("APNs token stored")
        } catch {
            // Not fatal and not worth a user-visible error: the next launch
            // registers again.
            log.notice("Could not store the APNs token: \(error.localizedDescription)")
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Family notices are worth showing while the app is open. There is no
    /// in-app banner that would duplicate them.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// A tap opens the person the reminder was about.
    ///
    /// This handler did not exist, so every dose, refill and appointment
    /// reminder opened the app on whatever record was last selected. The body
    /// has always said whose dose it is ("Dad: Warfarin"); the app just did not
    /// act on it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Pull the one value out before hopping: `userInfo` is
        // [AnyHashable: Any] and so not Sendable, and sending it across the
        // actor boundary is a data race the compiler correctly refuses.
        let raw = response.notification.request.content
            .userInfo[NotificationRoute.personKey] as? String
        guard let personID = raw.flatMap(UUID.init(uuidString:)) else { return }
        await MainActor.run {
            NotificationRoute.shared.route(to: personID)
        }
    }
}

/// APNs hands the device token to the app delegate and nowhere else, so SwiftUI
/// apps still need one.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await NotificationService.shared.store(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger(subsystem: "com.jackwallner.aging", category: "push")
            .notice("Remote notification registration failed: \(error.localizedDescription)")
        Task { @MainActor in NotificationService.shared.noteRemoteRegistrationFailed() }
    }
}
