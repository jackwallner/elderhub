import Foundation
import Testing

@testable import Aging

/// The indicator that hid everything.
///
/// `SettingsView` reports "Last synced" from `lastSyncedAt`, and for two builds
/// that timestamp advanced on every cycle in which nothing at all left or
/// reached the phone. The old rule withheld it only for `.offline`, and total
/// sync death is a `.server` failure, not an offline one. There was no signal
/// anywhere, on any device, that anything was wrong, which is why a database
/// four migrations behind the client got as far as a submitted build.
///
/// So the rule itself is what gets a test, not the network plumbing around it.
/// Serialized because these all drive the one shared coordinator the app uses.
@MainActor
@Suite("Sync coordinator", .serialized)
struct SyncCoordinatorTests {

    private func outcome(
        pulled: Int = 0, pushed: Int = 0, conflicts: Int = 0,
        needsReview: Int = 0, wasOffline: Bool = false, failure: String? = nil
    ) -> SyncEngine.Outcome {
        SyncEngine.Outcome(
            pulled: pulled, pushed: pushed, conflicts: conflicts,
            needsReview: needsReview, wasOffline: wasOffline, failure: failure
        )
    }

    @Test("A cycle that finished is the only thing that moves the timestamp")
    func aCleanCycleAdvancesTheTimestamp() {
        let coordinator = SyncCoordinator.shared
        let now = Date()

        coordinator.apply(outcome(pulled: 3, pushed: 2), now: now)

        #expect(coordinator.lastSyncedAt == now)
        #expect(coordinator.lastError == nil)
        #expect(coordinator.isOffline == false)
    }

    @Test("A server failure does not report the app as synced")
    func aServerFailureHoldsTheTimestamp() {
        let coordinator = SyncCoordinator.shared
        let synced = Date(timeIntervalSince1970: 1_754_294_400)
        coordinator.apply(outcome(pulled: 1), now: synced)

        // Exactly the shape of the shipped failure: one table pulled, nothing
        // pushed, no network problem at all.
        coordinator.apply(
            outcome(pulled: 1, failure: "Could not find the table 'public.providers'"),
            now: Date()
        )

        #expect(coordinator.lastSyncedAt == synced, "A failed cycle claimed the app was synced")
        #expect(coordinator.lastError != nil)
        #expect(coordinator.isOffline == false)
    }

    @Test("Being offline is reported as being offline, not as an error")
    func offlineIsItsOwnState() {
        let coordinator = SyncCoordinator.shared
        let synced = Date(timeIntervalSince1970: 1_754_294_400)
        coordinator.apply(outcome(pulled: 1), now: synced)

        coordinator.apply(outcome(wasOffline: true, failure: "No connection."), now: Date())

        // No signal is a normal state this app is built for, and Settings says
        // "showing your saved copy" rather than "couldn't sync" for it.
        #expect(coordinator.isOffline)
        #expect(coordinator.lastSyncedAt == synced)
    }

    @Test("A failure clears once a later cycle succeeds")
    func aRecoveredCycleClearsTheError() {
        let coordinator = SyncCoordinator.shared
        coordinator.apply(outcome(failure: "Could not find the table 'public.providers'"), now: Date())
        #expect(coordinator.lastError != nil)

        let recovered = Date()
        coordinator.apply(outcome(pulled: 4, pushed: 1), now: recovered)

        #expect(coordinator.lastError == nil)
        #expect(coordinator.lastSyncedAt == recovered)
    }

    @Test("Conflicts are carried through untouched, whatever else happened")
    func conflictsAreReportedIndependently() {
        let coordinator = SyncCoordinator.shared
        coordinator.apply(outcome(conflicts: 2, needsReview: 1, failure: "server said no"), now: Date())
        #expect(coordinator.conflictCount == 2)
    }
}
