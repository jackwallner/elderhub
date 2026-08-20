import Foundation
import Observation

/// Where a tapped notification wants the app to land.
///
/// Every reminder this app schedules is about one named person ("Dad:
/// Warfarin"), and until now tapping one opened the app wherever it was last
/// left. On a phone tracking one person that is invisible; on a phone tracking
/// two it is wrong about half the time, and the failure is silent: the reader
/// sees a plausible screen with the wrong parent's doses on it and ticks one
/// off.
///
/// A separate object from `AppNavigator` because the notification centre
/// delegate is a service-layer singleton that fires before any view exists, so
/// it needs somewhere to put the answer that does not depend on the view tree
/// being up. `RootView` observes it and hands it to the tab that can act on it.
@MainActor
@Observable
final class NotificationRoute {
    static let shared = NotificationRoute()

    /// The `userInfo` key every scheduled request carries. One key, written in
    /// one place, so a payload cannot drift from the reader.
    ///
    /// `nonisolated` because the scheduler is an actor and writes this key off
    /// the main actor; it is a constant string, so there is nothing to isolate.
    nonisolated static let personKey = "personID"

    /// Set on tap, cleared by whoever consumed it. Optional rather than a
    /// stream: only the most recent tap matters, and replaying an old one on
    /// the next launch would move someone off the screen they opened.
    private(set) var pendingPersonID: UUID?

    private init() {}

    func route(to personID: UUID) {
        pendingPersonID = personID
    }

    func consume() -> UUID? {
        defer { pendingPersonID = nil }
        return pendingPersonID
    }
}
