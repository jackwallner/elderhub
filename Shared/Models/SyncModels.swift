import Foundation
import SwiftData

// MARK: - Group membership

enum GroupRole: String, Codable, CaseIterable, Sendable {
    case owner, caregiver, subject

    /// "Staff" is the line the database draws too: owner and caregiver share
    /// every read and write, and the split that matters is against `subject`.
    var isStaff: Bool { self == .owner || self == .caregiver }

    var label: String {
        switch self {
        case .owner: return "Organizer"
        case .caregiver: return "Caregiver"
        case .subject: return "Being supported"
        }
    }
}

/// Local mirror of `groups` + this device's row in `group_members`.
///
/// Cached rather than fetched because role gating has to work offline: an app
/// that cannot tell whether you are a caregiver until the network answers has
/// to either block or guess, and both are wrong in an emergency room.
@Model
final class CareGroup {
    var id: UUID = UUID()
    var name: String = ""
    var roleRaw: String = GroupRole.owner.rawValue
    var joinedAt: Date = Date()
    /// Group-scoped entitlement, mirrored from `group_billing`. One person in
    /// the family pays and everyone is covered.
    var entitlement: String = "free"
    var entitlementExpiresAt: Date?
    var isLifetime: Bool = false
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), name: String, role: GroupRole) {
        self.id = id
        self.name = name
        self.roleRaw = role.rawValue
        self.joinedAt = Date()
        self.updatedAt = Date()
    }

    var role: GroupRole {
        get { GroupRole(rawValue: roleRaw) ?? .subject }
        set { roleRaw = newValue.rawValue }
    }

    /// How many invitations are outstanding, mirrored from `loadPendingInvites`.
    ///
    /// Cached for the same reason the role is: the setup checklist has to be
    /// able to say whether anyone has actually been invited without waiting on
    /// a request, and a tick that unticks itself every time the phone goes
    /// offline is worse than no tick.
    var pendingInviteCount: Int = 0

    /// Deliberately does not consider the check-in feature. See `CheckInRecord`.
    var hasPlus: Bool {
        guard entitlement == "plus" else { return false }
        if isLifetime { return true }
        guard let entitlementExpiresAt else { return false }
        return entitlementExpiresAt > Date()
    }
}

/// Local mirror of one row of `group_members`, joined to that member's profile
/// name.
///
/// Not a `SyncableRecord`: it is a read-through cache of a table this client can
/// never write, refreshed by `GroupService.loadMembers` and dropped wholesale by
/// `forgetGroupLocally`. It exists because the member list was held only in
/// memory, so a cold launch with no signal showed the subject an empty "who can
/// see me" screen, which is the one screen that must never be blank: consent to
/// being watched means nothing without the list of who is watching.
@Model
final class CachedGroupMember {
    /// The member's `user_id`, which is also the row's identity.
    var id: UUID = UUID()
    var groupID: UUID = UUID()
    var displayName: String = ""
    var roleRaw: String = GroupRole.caregiver.rawValue
    var joinedAt: Date = Date()
    var isSelf: Bool = false
    var cachedAt: Date = Date()

    init(
        id: UUID,
        groupID: UUID,
        displayName: String,
        role: GroupRole,
        joinedAt: Date,
        isSelf: Bool
    ) {
        self.id = id
        self.groupID = groupID
        self.displayName = displayName
        self.roleRaw = role.rawValue
        self.joinedAt = joinedAt
        self.isSelf = isSelf
        self.cachedAt = Date()
    }

    var role: GroupRole {
        get { GroupRole(rawValue: roleRaw) ?? .caregiver }
        set { roleRaw = newValue.rawValue }
    }
}

// MARK: - Check-in

enum CheckInSource: String, Codable, Sendable {
    /// The person pressed their own button.
    case selfPressed = "self"
    /// A caregiver recorded it for someone who has no phone.
    case caregiverManual = "caregiver_manual"
}

@Model
final class CheckInRecord {
    var id: UUID = UUID()
    var groupID: UUID?
    var personID: UUID = UUID()
    var sourceRaw: String = CheckInSource.selfPressed.rawValue
    var pressedByName: String = ""
    /// When the button was pressed, not when it synced. A check-in made in a
    /// basement with no signal is still a check-in from when it happened.
    var pressedAt: Date = Date()
    var note: String = ""
    var updatedAt: Date = Date()
    var isDirty: Bool = true

    init(
        id: UUID = UUID(),
        groupID: UUID?,
        personID: UUID,
        source: CheckInSource,
        pressedByName: String = "",
        pressedAt: Date = Date()
    ) {
        self.id = id
        self.groupID = groupID
        self.personID = personID
        self.sourceRaw = source.rawValue
        self.pressedByName = pressedByName
        self.pressedAt = pressedAt
        self.updatedAt = Date()
    }

    var source: CheckInSource {
        get { CheckInSource(rawValue: sourceRaw) ?? .selfPressed }
        set { sourceRaw = newValue.rawValue }
    }
}

/// The agreed daily window, stored as minutes from midnight plus an IANA zone,
/// matching `Medication.scheduleMinutes`. Storing an absolute time would drift
/// the moment anyone travels or the clocks change.
@Model
final class CheckInSettings {
    var personID: UUID = UUID()
    var groupID: UUID?
    var enabled: Bool = false
    var windowStartMinute: Int = 8 * 60
    var windowEndMinute: Int = 20 * 60
    var graceMinutes: Int = 60
    var timeZoneIdentifier: String = TimeZone.current.identifier
    var updatedAt: Date = Date()
    var isDirty: Bool = true

    init(personID: UUID, groupID: UUID?) {
        self.personID = personID
        self.groupID = groupID
        self.timeZoneIdentifier = TimeZone.current.identifier
        self.updatedAt = Date()
    }
}

// MARK: - Outbox

enum OutboxStatus: String, Codable, Sendable {
    case pending
    /// Retrying with backoff after a transient failure.
    case retrying
    /// The server refused it for a reason retrying cannot fix, most often a
    /// role that changed while this device was offline. Surfaced to the user
    /// rather than retried forever.
    case needsReview
}

/// A local write waiting to reach the server.
///
/// Writes queue here rather than going straight out so that pressing "taken" in
/// a lift still works, and so a failed push is a queued row rather than lost
/// data. Coalescing is per entity kind, decided by the engine: two edits to the
/// same medication collapse into one upsert because only the final state
/// matters, while two dose logs never collapse because each is a distinct
/// event that happened.
@Model
final class OutboxEntry {
    var id: UUID = UUID()
    var entityTypeRaw: String = ""
    var entityID: UUID = UUID()
    var groupID: UUID?
    var createdAt: Date = Date()
    var attempts: Int = 0
    var statusRaw: String = OutboxStatus.pending.rawValue
    var lastError: String = ""
    var notBefore: Date = Date()

    init(entityType: SyncEntity, entityID: UUID, groupID: UUID?) {
        self.id = UUID()
        self.entityTypeRaw = entityType.rawValue
        self.entityID = entityID
        self.groupID = groupID
        self.createdAt = Date()
        self.notBefore = Date()
    }

    var entityType: SyncEntity {
        get { SyncEntity(rawValue: entityTypeRaw) ?? .person }
        set { entityTypeRaw = newValue.rawValue }
    }

    var status: OutboxStatus {
        get { OutboxStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}

// MARK: - Cursor

/// Per-entity pull cursor.
///
/// The timestamp is always the server's `updated_at`, never the device clock. A
/// phone whose clock is fast would otherwise write a cursor into the future and
/// stop seeing its family's changes, with no error anywhere. `lastID` breaks
/// ties so rows sharing a timestamp across a page boundary are neither skipped
/// nor fetched twice.
@Model
final class SyncCursor {
    var entityTypeRaw: String = ""
    var lastUpdatedAt: Date?
    var lastID: UUID?
    var lastSyncedAt: Date?

    init(entityType: SyncEntity) {
        self.entityTypeRaw = entityType.rawValue
    }

    var entityType: SyncEntity {
        get { SyncEntity(rawValue: entityTypeRaw) ?? .person }
        set { entityTypeRaw = newValue.rawValue }
    }
}

// MARK: - Entity catalogue

enum SyncEntity: String, CaseIterable, Sendable {
    case person = "care_recipients"
    case medication = "medications"
    case doseLog = "dose_logs"
    case visit = "visits"
    case vital = "vital_readings"
    case emergencyContact = "emergency_contacts"
    case provider = "providers"
    /// Falls, ER visits, symptoms and the rest of the incident/symptom log
    /// (plan82 slice D).
    case careEvent = "care_events"
    /// The family's shared to-do list against one recipient.
    case careTask = "care_tasks"
    /// Free-form notes kept against one recipient (migration 0014).
    case note = "care_notes"
    /// What the family pays on this person's behalf (migration 0017).
    case bill = "bills"
    case checkIn = "check_ins"
    case checkInSettings = "check_in_settings"

    var table: String { rawValue }

    /// Pull order. Parents before children, so a medication never lands before
    /// the recipient it points at. Providers sit right after person: nothing
    /// but a recipient stands between them, and medications/visits resolve a
    /// `providerID` lazily rather than through a stored relationship, so they
    /// do not need providers pulled before them.
    static var pullOrder: [SyncEntity] {
        [.person, .provider, .medication, .doseLog, .visit, .vital, .emergencyContact,
         .careEvent, .careTask, .note, .bill, .checkIn, .checkInSettings]
    }

    /// Whether two queued writes to the same row may collapse into one.
    /// False for anything that is a record of an event rather than a state.
    var isCoalescable: Bool {
        switch self {
        case .doseLog, .checkIn: return false
        default: return true
        }
    }
}

// MARK: - Recording a local write

/// The four columns every syncable row carries, plus the table it belongs to.
///
/// Exists so that recording a local write is one call that cannot be got half
/// right. Every screen used to repeat "set `isDirty`, bump `updatedAt`, queue
/// the right `SyncEntity`" by hand, and most of them forgot at least one part,
/// which is silent: the row looks saved, renders everywhere, and simply never
/// leaves the phone.
protocol SyncableRecord: AnyObject {
    var id: UUID { get }
    var groupID: UUID? { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var isDirty: Bool { get set }
    static var syncEntity: SyncEntity { get }
}

extension Person: SyncableRecord { static var syncEntity: SyncEntity { .person } }
extension Medication: SyncableRecord { static var syncEntity: SyncEntity { .medication } }
extension DoseLog: SyncableRecord { static var syncEntity: SyncEntity { .doseLog } }
extension Visit: SyncableRecord { static var syncEntity: SyncEntity { .visit } }
extension VitalReading: SyncableRecord { static var syncEntity: SyncEntity { .vital } }
extension EmergencyContact: SyncableRecord { static var syncEntity: SyncEntity { .emergencyContact } }
extension Provider: SyncableRecord { static var syncEntity: SyncEntity { .provider } }
extension CareEvent: SyncableRecord { static var syncEntity: SyncEntity { .careEvent } }
extension CareTask: SyncableRecord { static var syncEntity: SyncEntity { .careTask } }
extension CareNote: SyncableRecord { static var syncEntity: SyncEntity { .note } }
extension Bill: SyncableRecord { static var syncEntity: SyncEntity { .bill } }

@MainActor
extension SyncableRecord {
    /// Call after any local create or edit. Saves the row before queueing it so
    /// a fast sync cannot read the old value or miss a just-inserted row.
    /// Safe before the install has a group: the entry waits in the outbox and
    /// drains after adoption.
    ///
    /// `updatedAt` is bumped here even though the server owns the column on the
    /// way back in, because `isRealConflict` compares the two: without a local
    /// bump, a sibling's edit made *before* yours still reads as newer and
    /// flags a conflict that never happened.
    func recordLocalChange(in context: ModelContext) {
        updatedAt = Date()
        isDirty = true
        try? context.save()
        SyncCoordinator.shared.enqueue(Self.syncEntity, id: id)
    }

    /// Deletes by tombstone, never by removing the row.
    ///
    /// The row has to survive locally until the outbox pushes it: the push
    /// reads the row to build the DTO, so a row deleted outright can never be
    /// sent, and the delete would live and die on this one phone while the rest
    /// of the family keeps showing a medication that was stopped. `markSynced`
    /// clears it out once the server has it.
    func tombstone(in context: ModelContext) {
        deletedAt = Date()
        recordLocalChange(in: context)
    }
}
