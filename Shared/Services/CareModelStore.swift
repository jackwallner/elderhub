import Foundation
import SwiftData

/// Owns the SwiftData container.
///
/// This store is the app's source of truth for reading, and that is a deliberate
/// architectural choice rather than a leftover from the local-only version. The
/// scenario the whole app is built around is someone standing in an emergency
/// room with no signal who needs a medication list and an allergy list on screen
/// immediately. Cloud sync writes into this store; it never sits in front of it.
///
/// Because it now holds another person's health data, the file is explicitly
/// marked `completeUntilFirstUserAuthentication`: encrypted at rest until the
/// first unlock after boot, and readable thereafter so background sync and
/// notification handling still work. `complete` would be stronger but would make
/// the store unreadable whenever the phone is locked, which breaks exactly the
/// background paths this app depends on.
enum CareModelStore {
    static let schema = Schema([
        Person.self,
        Medication.self,
        DoseLog.self,
        Visit.self,
        VitalReading.self,
        EmergencyContact.self,
        Provider.self,
        CareEvent.self,
        CareTask.self,
        CareNote.self,
        Bill.self,
        CareGroup.self,
        CachedGroupMember.self,
        CheckInRecord.self,
        CheckInSettings.self,
        OutboxEntry.self,
        SyncCursor.self
    ])

    static let sharedModelContainer: ModelContainer = {
        let url = storeURL

        if let container = makeContainer(url: url) {
            return container
        }

        // A failed migration or a half-written file can leave the store unreadable.
        // For anyone not in a family group this is the only copy of the records,
        // so move it aside instead of deleting it, then retry with a fresh store.
        quarantineStore(at: url)

        if let container = makeContainer(url: url) {
            return container
        }

        let inMemory = ModelConfiguration(
            "Aging",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [inMemory])
        } catch {
            fatalError("CareModelStore could not initialize: \(error)")
        }
    }()

    /// Deletes the store from disk. DEBUG-only, and called from exactly one
    /// place: the `-uitest-wipe-store` launch flag, before the container is
    /// first built. Nothing in a shipped app may reach this.
    #if DEBUG
    static func wipeStoreFilesForTesting() {
        let url = storeURL
        for file in [url, url.appendingPathExtension("wal"), url.appendingPathExtension("shm")] {
            try? FileManager.default.removeItem(at: file)
        }
    }
    #endif

    /// Renames the store and its SQLite sidecars to `<name>.corrupt-<uuid>` so a
    /// fresh store can open at `url`. The move keeps the file's protection class.
    /// Returns the quarantined copies.
    @discardableResult
    static func quarantineStore(at url: URL, fileManager: FileManager = .default) -> [URL] {
        let suffix = ".corrupt-\(UUID().uuidString)"
        let candidates = [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
            url.appendingPathExtension("wal"),
            url.appendingPathExtension("shm")
        ]
        var moved: [URL] = []
        for file in candidates where fileManager.fileExists(atPath: file.path) {
            let destination = URL(fileURLWithPath: file.path + suffix)
            if (try? fileManager.moveItem(at: file, to: destination)) != nil {
                moved.append(destination)
            }
        }
        return moved
    }

    /// In-memory container for tests and previews.
    static func makeInMemoryContainer() -> ModelContainer {
        let config = ModelConfiguration(
            "AgingPreview",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not build in-memory container: \(error)")
        }
    }

    private static func makeContainer(url: URL) -> ModelContainer? {
        let config = ModelConfiguration(
            "Aging",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            return nil
        }
        applyFileProtection(to: url)
        return container
    }

    /// Applied to the store and its write-ahead log. Set explicitly rather than
    /// relying on the platform default, and re-applied on every container build
    /// so the quarantine-and-retry path above cannot silently recreate the file
    /// without it.
    private static func applyFileProtection(to url: URL) {
        let manager = FileManager.default
        let files = [
            url,
            url.appendingPathExtension("wal"),
            url.appendingPathExtension("shm")
        ]
        for file in files where manager.fileExists(atPath: file.path) {
            try? manager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: file.path
            )
        }
    }

    private static var storeURL: URL {
        let manager = FileManager.default
        guard let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return manager.temporaryDirectory.appendingPathComponent("Aging.store")
        }

        // Application Support does not exist on first launch, and CoreData will not
        // create it. Without this the first run logs a wall of stat/sandbox errors
        // and silently falls through to the in-memory store, losing everything the
        // user enters in that session.
        if !manager.fileExists(atPath: base.path) {
            try? manager.createDirectory(at: base, withIntermediateDirectories: true)
        }

        return base.appendingPathComponent("Aging.store")
    }
}
