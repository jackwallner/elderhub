import Foundation
import SwiftData

/// Signing out removes the shared copy. Count what only this phone still holds
/// before allowing that account boundary to close.
@MainActor
enum SignOutProtection {
    static func prepare(
        in container: ModelContainer, sync: () async -> Void
    ) async throws -> String? {
        guard try !pendingChanges(in: container).isEmpty else { return nil }
        await sync()
        let remaining = try pendingChanges(in: container)
        guard !remaining.isEmpty else { return nil }
        return "These changes could not be synced: \(remaining.joined(separator: ", ")). Signing out will permanently discard them from this phone. Your family will not receive them. Cancel to keep them and stay signed in."
    }

    static func pendingChanges(in container: ModelContainer) throws -> [String] {
        // A fresh context sees the engine's saved acknowledgements after sync.
        let context = ModelContext(container)
        var pending: [SyncEntity: Set<UUID>] = [:]
        for entry in try context.fetch(FetchDescriptor<OutboxEntry>()) where entry.groupID != nil {
            pending[entry.entityType, default: []].insert(entry.entityID)
        }

        // Enqueue runs asynchronously. A just-saved edit may still be dirty
        // without an outbox entry, and tombstones also need to reach the family.
        func include<T: PersistentModel & SyncableRecord>(_ type: T.Type) throws {
            for row in try context.fetch(FetchDescriptor<T>()) where row.groupID != nil && row.isDirty {
                pending[T.syncEntity, default: []].insert(row.id)
            }
        }
        try include(Person.self)
        try include(Provider.self)
        try include(Medication.self)
        try include(DoseLog.self)
        try include(Visit.self)
        try include(VitalReading.self)
        try include(EmergencyContact.self)
        try include(CareEvent.self)
        try include(CareTask.self)
        try include(CareNote.self)
        try include(Bill.self)
        for row in try context.fetch(FetchDescriptor<CheckInRecord>()) where row.groupID != nil && row.isDirty {
            pending[.checkIn, default: []].insert(row.id)
        }
        for row in try context.fetch(FetchDescriptor<CheckInSettings>()) where row.groupID != nil && row.isDirty {
            pending[.checkInSettings, default: []].insert(row.personID)
        }

        return SyncEntity.pullOrder.compactMap { entity in
            guard let count = pending[entity]?.count, count > 0 else { return nil }
            let labels: (String, String) = switch entity {
            case .person: ("person", "people")
            case .provider: ("provider", "providers")
            case .medication: ("medication", "medications")
            case .doseLog: ("dose", "doses")
            case .visit: ("visit", "visits")
            case .vital: ("vital reading", "vital readings")
            case .emergencyContact: ("contact", "contacts")
            case .careEvent: ("care event", "care events")
            case .careTask: ("task", "tasks")
            case .note: ("note", "notes")
            case .bill: ("bill", "bills")
            case .checkIn: ("check-in", "check-ins")
            case .checkInSettings: ("check-in setting", "check-in settings")
            }
            return "\(count) \(count == 1 ? labels.0 : labels.1)"
        }
    }
}
