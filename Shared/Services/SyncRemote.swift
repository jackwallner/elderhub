import Foundation
import Supabase

// MARK: - DTOs

/// Everything that crosses the wire is a plain `Sendable` struct. SwiftData's
/// `@Model` classes are not `Sendable` and must never leave the actor that owns
/// their `ModelContext`, so the sync engine converts at the boundary.
protocol SyncDTO: Codable, Sendable, Identifiable {
    static var entity: SyncEntity { get }
    /// The primary-key column, which is not always called `id`.
    /// `check_in_settings` is keyed on the recipient, one row per person.
    static var idColumn: String { get }
    var id: UUID { get }
    var updated_at: Date? { get }
    var deleted_at: Date? { get }
}

extension SyncDTO {
    static var idColumn: String { "id" }
}

/// Where a pull left off. Compound because a timestamp alone is not a stable
/// cursor: several rows written in the same transaction share `updated_at` to
/// the microsecond, and a page boundary landing in the middle of them would
/// either skip rows or loop on them forever.
struct SyncPage: Sendable, Equatable {
    var updatedAt: Date
    var id: UUID
}

struct PersonDTO: SyncDTO {
    static let entity = SyncEntity.person
    var id: UUID
    var group_id: UUID
    var linked_user_id: UUID?
    var name: String
    var relationship: String
    var birth_date: Date?
    var blood_type: String
    var color_index: Int
    var allergies: [String]
    var conditions: [String]
    var notes: String
    /// The client sends only the timestamp. `surrogate_attested_by` is stamped
    /// by a server trigger (0007), so a device cannot claim someone else made
    /// the attestation, and a later sync cannot blank out who did.
    var surrogate_attested_at: Date?
    var last_check_in_at: Date?
    var created_by_name: String?
    var updated_at: Date?
    var deleted_at: Date?
}

struct MedicationDTO: SyncDTO {
    static let entity = SyncEntity.medication
    var id: UUID
    var group_id: UUID
    var care_recipient_id: UUID
    var name: String
    var strength: String
    var form: String
    var purpose: String
    var prescriber: String
    var pharmacy: String
    /// Links to a `providers` row (plan82 slice C). The free-text `prescriber`
    /// and `pharmacy` above are never cleared, so an old record keeps working
    /// with no id set.
    var provider_id: UUID?
    var pharmacy_id: UUID?
    var instructions: String
    var schedule_minutes: [Int]
    var weekdays: [Int]
    var is_as_needed: Bool
    var is_active: Bool
    var start_date: Date
    var end_date: Date?
    /// Whether the supply is counted at all. Split out from
    /// `quantity_remaining` in 0016: zero used to mean both "not tracked" and
    /// "empty", which broke refill warnings at the moment a bottle ran out.
    var tracks_refills: Bool
    var quantity_remaining: Double
    var units_per_dose: Double
    var refill_threshold_days: Int
    var last_filled_at: Date?
    var updated_by_name: String?
    var updated_at: Date?
    var deleted_at: Date?
}

struct DoseLogDTO: SyncDTO {
    static let entity = SyncEntity.doseLog
    var id: UUID
    var group_id: UUID
    var medication_id: UUID
    var scheduled_at: Date
    var recorded_at: Date
    var status: String
    var recorded_by_name: String
    var note: String
    var updated_at: Date?
    var deleted_at: Date?
}

struct VisitDTO: SyncDTO {
    static let entity = SyncEntity.visit
    var id: UUID
    var group_id: UUID
    var care_recipient_id: UUID
    var date: Date
    var provider: String
    /// Links to a `providers` row (plan82 slice C). The free-text `provider`
    /// above is never cleared.
    var provider_id: UUID?
    var specialty: String
    var reason: String
    var notes: String
    var follow_up: String
    var next_appointment: Date?
    var updated_at: Date?
    var deleted_at: Date?
}

struct VitalDTO: SyncDTO {
    static let entity = SyncEntity.vital
    var id: UUID
    var group_id: UUID
    var care_recipient_id: UUID
    var kind: String
    var primary_value: Double
    var secondary_value: Double?
    var recorded_at: Date
    var note: String
    var updated_at: Date?
    var deleted_at: Date?
}

struct EmergencyContactDTO: SyncDTO {
    static let entity = SyncEntity.emergencyContact
    var id: UUID
    var group_id: UUID
    var care_recipient_id: UUID
    var name: String
    var relationship: String
    var phone: String
    var is_primary: Bool
    var updated_at: Date?
    var deleted_at: Date?
}

struct ProviderDTO: SyncDTO {
    static let entity = SyncEntity.provider
    var id: UUID
    var group_id: UUID
    var care_recipient_id: UUID
    var name: String
    var specialty: String
    var phone: String
    var address: String
    var portal_url: String
    var notes: String
    var is_pharmacy: Bool
    var updated_at: Date?
    var deleted_at: Date?
}

/// Falls, ER visits, symptoms and the rest of the incident/symptom log
/// (plan82 slice D). `recorded_by_name` matters more here than on most other
/// DTOs, so it is carried the same way `DoseLogDTO.recorded_by_name` is
/// rather than the `created_by_name`/`updated_by_name` pair `VitalDTO` skips.
struct CareEventDTO: SyncDTO {
    static let entity = SyncEntity.careEvent
    var id: UUID
    var group_id: UUID
    var care_recipient_id: UUID
    var kind: String
    var occurred_at: Date
    var severity: Int
    var note: String
    var recorded_by_name: String
    var updated_at: Date?
    var deleted_at: Date?
}

/// The family's shared to-do list. `assignee_name` and `completed_by_name` are
/// carried as names for the same reason `DoseLogDTO.recorded_by_name` is: the
/// sentence the family needs ("Sarah still has the pharmacy call") has to render
/// from the local store with no lookup and no network.
struct CareTaskDTO: SyncDTO {
    static let entity = SyncEntity.careTask
    var id: UUID
    var group_id: UUID
    var care_recipient_id: UUID
    var title: String
    var notes: String
    var due_at: Date?
    var priority: String
    var recurrence: String
    var assignee_user_id: UUID?
    var assignee_name: String
    var completed_at: Date?
    var completed_by_name: String
    var created_by_name: String
    var updated_at: Date?
    var deleted_at: Date?
}

/// A free-form note. The body crosses the wire as ordinary text, like every
/// other free-text column in this schema, and is protected by exactly the same
/// RLS as the medication list. Nothing in the UI asks for credentials, and if
/// that ever changes this DTO is where the encryption would have to go in.
struct CareNoteDTO: SyncDTO {
    static let entity = SyncEntity.note
    var id: UUID
    var group_id: UUID
    var care_recipient_id: UUID
    var title: String
    var body: String
    var is_pinned: Bool
    var created_by_name: String
    var updated_at: Date?
    var deleted_at: Date?
}

/// A bill. Ordinary text and an amount, under the same RLS as the medication
/// list. Nothing here is a credential: no account number, no login, no card,
/// and the editor says so where someone is about to type. If that ever changes,
/// this DTO is where the encryption would have to go in, exactly as for
/// `CareNoteDTO`.
struct BillDTO: SyncDTO {
    static let entity = SyncEntity.bill
    var id: UUID
    var group_id: UUID
    var care_recipient_id: UUID
    var payee: String
    var amount: Double
    var notes: String
    var category: String
    var recurrence: String
    var due_at: Date?
    var is_auto_pay: Bool
    var paid_at: Date?
    var paid_by_name: String
    var created_by_name: String
    var updated_at: Date?
    var deleted_at: Date?
}

struct CheckInDTO: SyncDTO {
    static let entity = SyncEntity.checkIn
    var id: UUID
    var group_id: UUID
    var care_recipient_id: UUID
    var source: String
    var pressed_by: UUID?
    var pressed_by_name: String
    var pressed_at: Date
    var note: String
    var updated_at: Date?
    /// Check-ins are never deleted. Present only to satisfy `SyncDTO`.
    var deleted_at: Date? { nil }
}

/// One row per recipient, keyed on the recipient rather than on an `id` of its
/// own. The subject's device pulls this so it can schedule the local reminder
/// (D26) from the window the family agreed.
struct CheckInSettingsDTO: SyncDTO {
    static let entity = SyncEntity.checkInSettings
    static let idColumn = "care_recipient_id"

    var care_recipient_id: UUID
    var group_id: UUID
    var enabled: Bool
    var window_start_minute: Int
    var window_end_minute: Int
    var grace_minutes: Int
    var timezone: String
    var updated_at: Date?

    /// Computed, so `Codable` synthesis leaves it out of the wire payload and
    /// the upsert does not try to write a column that does not exist.
    var id: UUID { care_recipient_id }
    var deleted_at: Date? { nil }
}

// MARK: - Remote

/// Fronted by a protocol so the engine can be tested without a backend. Cursor
/// pagination, version conflicts and role-changed rejections are all
/// deterministic against a fake and effectively untestable against a live one.
protocol SyncRemote: Sendable {
    func pull<T: SyncDTO>(_ type: T.Type, after page: SyncPage?, limit: Int) async throws -> [T]
    func push<T: SyncDTO>(_ rows: [T]) async throws
}

/// Why a push failed, which decides whether the outbox retries or gives up.
enum SyncError: Error, Equatable {
    /// Network. Keep the entry queued and try again later.
    case offline
    /// The server refused on authorization grounds. Retrying cannot fix this:
    /// the most likely cause is a caregiver being demoted while their phone was
    /// offline, and their queued medication edits are no longer allowed.
    case rejected(String)
    case server(String)
}

struct SupabaseSyncRemote: SyncRemote {
    let client: SupabaseClient
    let groupID: UUID

    func pull<T: SyncDTO>(_ type: T.Type, after page: SyncPage?, limit: Int) async throws -> [T] {
        do {
            var query = client
                .from(T.entity.table)
                .select()
                .eq("group_id", value: groupID)

            if let page {
                // Strictly after (updated_at, id) in lexicographic order. `or`
                // is how PostgREST expresses the compound comparison.
                query = query.or(
                    "updated_at.gt.\(Self.iso(page.updatedAt))," +
                    "and(updated_at.eq.\(Self.iso(page.updatedAt))," +
                    "\(T.idColumn).gt.\(page.id.uuidString))"
                )
            }

            return try await query
                .order("updated_at", ascending: true)
                .order(T.idColumn, ascending: true)
                .limit(limit)
                .execute()
                .value
        } catch {
            throw Self.classify(error)
        }
    }

    func push<T: SyncDTO>(_ rows: [T]) async throws {
        guard !rows.isEmpty else { return }
        do {
            // Upsert on the primary key. Because the client generated these
            // UUIDs in the first place, re-sending a row the server already has
            // is a no-op rather than a duplicate, which is what makes retrying
            // safe after a timeout where we never learned the outcome.
            try await client
                .from(T.entity.table)
                .upsert(rows, onConflict: T.idColumn)
                .execute()
        } catch {
            throw Self.classify(error)
        }
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func classify(_ error: Error) -> SyncError {
        if error is URLError { return .offline }
        if (error as NSError).domain == NSURLErrorDomain { return .offline }

        // A row the client cannot decode is a schema disagreement, not a bad
        // network, and calling it `.offline` is how the last one hid: the app
        // reported itself offline while sitting on five bars. Named explicitly
        // so it reaches `lastError` and a person sees it.
        if error is DecodingError { return .server("This app is out of date for the server's data.") }

        if let postgrest = error as? PostgrestError {
            // 42501 is insufficient_privilege, which is what an RLS policy
            // returns when this user is no longer allowed to write this row.
            if postgrest.code == "42501" || postgrest.code == "PGRST301" {
                return .rejected(postgrest.message)
            }
            // Everything else, including PGRST204 (no such column) and PGRST205
            // (no such table), the two the missing migrations produced. Both are
            // fixed by a deploy rather than by the user, so they stay retryable
            // `.server` failures rather than becoming a "needs a look" the
            // family is asked to resolve and cannot.
            return .server(postgrest.message)
        }

        return .offline
    }
}
