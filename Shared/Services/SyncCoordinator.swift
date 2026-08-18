import Foundation
import OSLog
import SwiftData
import Supabase

/// Drives the `SyncEngine` from the UI layer and owns the enqueue side of the
/// outbox.
///
/// Foreground-only by design (D22). iOS grants background refresh
/// unpredictably, so anything that has to be reliable is either server-driven
/// (escalation) or a local notification (the parent's own reminder). Sync is
/// neither: it is allowed to be late, as long as it is never lossy.
@MainActor
@Observable
final class SyncCoordinator {
    static let shared = SyncCoordinator()

    private(set) var lastOutcome: SyncEngine.Outcome?
    private(set) var lastSyncedAt: Date?
    private(set) var isSyncing = false
    private(set) var conflictCount = 0
    /// Why the last cycle did not finish, or nil if it did. Nothing reads this
    /// on the way to rendering data (I1): it is reported after the fact, in
    /// Settings, and never sits in front of the medication list.
    private(set) var lastError: String?

    /// The network was the problem, rather than the server. Worth separating,
    /// because "you are offline" is a normal state this app is built for and
    /// "the server refused" is not.
    private(set) var isOffline = false

    private let log = Logger(subsystem: "com.jackwallner.aging", category: "sync")
    private let engine = SyncEngine(modelContainer: CareModelStore.sharedModelContainer)

    private var auth: AuthService { .shared }
    private var groups: GroupService { .shared }

    private init() {}

    /// A local change that has to reach the family. Safe to call for rows that
    /// have no group yet: they queue, and the queue drains after adoption.
    func enqueue(_ entity: SyncEntity, id: UUID) {
        let groupID = groups.activeGroupID
        Task { await engine.enqueue(entity: entity, id: id, groupID: groupID) }
    }

    func syncNow() async {
        guard !isSyncing else { return }
        guard auth.isSignedIn, let groupID = groups.activeGroupID else { return }
        guard !groups.requiresTransparency else { return }

        isSyncing = true
        defer { isSyncing = false }

        let remote = SupabaseSyncRemote(client: auth.client, groupID: groupID)
        let outcome = await engine.sync(remote: remote, groupID: groupID)
        apply(outcome)
    }

    /// Folds one cycle's result into the published state.
    ///
    /// Split out of `syncNow` and left non-private on purpose: this is the rule
    /// that hid total sync failure for two builds, and it needs to be testable
    /// without a container, a network or a signed-in user.
    func apply(_ outcome: SyncEngine.Outcome, now: Date = Date()) {
        lastOutcome = outcome
        conflictCount = outcome.conflicts
        lastError = outcome.failure
        isOffline = outcome.wasOffline

        // Only a cycle that actually completed. The old rule advanced this on
        // anything that was not an outright network failure, so a total sync
        // death reported "Last synced: just now" on every pass, on every
        // device, which is precisely why nobody noticed it for two builds.
        if outcome.isComplete { lastSyncedAt = now }

        log.info("Sync: pulled \(outcome.pulled), pushed \(outcome.pushed), review \(outcome.needsReview), failure \(outcome.failure ?? "none")")
    }

    /// One-time adoption of a local-only install into a freshly created group.
    func adoptLocalData(into groupID: UUID) async {
        await engine.adoptLocalData(into: groupID)
        await syncNow()
    }

    /// Moves one private record into the circle this device belongs to. Always
    /// user-initiated: see `SyncEngine.adoptPerson`.
    func adoptPerson(id personID: UUID, into groupID: UUID) async {
        await engine.adoptPerson(id: personID, into: groupID)
        await syncNow()
    }

    // MARK: - Conflicts

    /// The records waiting on a decision, for the review screen.
    func conflicts() async -> [SyncEngine.ConflictSummary] {
        await engine.conflicts()
    }

    func resolveKeepingLocal(id: UUID) async {
        await engine.resolveKeepingLocal(id: id)
        conflictCount = await engine.conflictCount()
        await syncNow()
    }

    func resolveTakingRemote(id: UUID) async {
        await engine.resolveTakingRemote(id: id)
        conflictCount = await engine.conflictCount()
        await syncNow()
    }

    /// Recomputed without running a cycle, so the review screen's badge is
    /// right the moment it is opened rather than after the next sync.
    func refreshConflictCount() async {
        conflictCount = await engine.conflictCount()
    }
}
