import Foundation
import OSLog
import SwiftData
import Supabase

// MARK: - Wire types

/// A member as the family sees them. Deliberately not the `group_members` row:
/// the UI needs the display name, which lives on `profiles`.
struct GroupMember: Identifiable, Sendable, Equatable {
    var id: UUID
    var displayName: String
    var role: GroupRole
    var joinedAt: Date
    var isSelf: Bool
    /// Which of the circle's people this member can read (migration 0018).
    ///
    /// Default is `.all`, which is what every member had before the column
    /// existed and what a sibling should keep having. `.listed` is a deliberate
    /// act by the owner, for the neighbour who helps with Mom and has no reason
    /// to be reading Dad's bills.
    var accessScope: MemberAccessScope = .all
    /// The recipient ids this member was granted, meaningful only when
    /// `accessScope == .listed`.
    var visibleRecipientIDs: Set<UUID> = []

    /// Owners are unrestricted whatever the stored flag says, and the RPC
    /// refuses to set one. Mirrored here so the UI does not offer a control
    /// the server will reject (the enforcement is the policy, never this).
    var canBeRestricted: Bool { role == .caregiver }

    var resolvedName: String {
        if isSelf { return displayName.isEmpty ? "You" : "\(displayName) (you)" }
        return displayName.isEmpty ? "Family member" : displayName
    }
}

/// Whether a member sees the whole circle or a named list of it.
///
/// A string, cast at the boundary, matching `group_members.access_scope`. An
/// unknown value falls back to `.all` for the same reason every other enum in
/// this app does: a row written by a newer client must not make an older one
/// hide records it should be showing.
enum MemberAccessScope: String, Sendable, CaseIterable {
    case all
    case listed

    init(rawValue: String) {
        switch rawValue {
        case "listed": self = .listed
        default: self = .all
        }
    }
}

struct PendingInvite: Identifiable, Sendable, Equatable {
    var id: String { code }
    var code: String
    var email: String?
    var role: GroupRole
    var recipientID: UUID?
    var expiresAt: Date

    var isExpired: Bool { expiresAt <= Date() }
}

/// Why an invite code was refused. The server returns these as values rather
/// than raising, because a raised exception rolls back the rate-limit row that
/// the same call just wrote. See `accept_invite` in 0004.
enum InviteFailure: String, Sendable {
    case invalidCode = "invalid_code"
    case rateLimited = "rate_limited"
    case alreadyInGroup = "already_in_group"

    var message: String {
        switch self {
        case .invalidCode:
            return "That code did not work. Codes expire after 48 hours, so ask for a fresh one."
        case .rateLimited:
            return "Too many tries. Wait an hour and then try again."
        case .alreadyInGroup:
            return "This account already belongs to a care circle. Add Mom, Dad, or a partner to that circle so the same family can help everyone."
        }
    }
}

enum GroupServiceError: LocalizedError {
    case notSignedIn
    case noGroup
    case invite(InviteFailure)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in first."
        case .noGroup: return "You are not in a care circle yet."
        case .invite(let failure): return failure.message
        case .server(let message): return message
        }
    }
}

// MARK: - Service

/// Everything about *who is in this family and what they may do*.
///
/// Membership is cached into a local `CareGroup` row on every successful load,
/// and every read below prefers that cache. Role gating has to work with the
/// network down: an app that cannot decide whether you are a caregiver until a
/// server answers must either block or guess, and in an emergency room both are
/// the wrong answer.
///
/// Every mutation goes through a security-definer RPC rather than a table write.
/// `group_members` has no client insert or update policy at all, so there is no
/// second path that could drift from these.
@MainActor
@Observable
final class GroupService {
    static let shared = GroupService()

    private(set) var members: [GroupMember] = []
    private(set) var pendingInvites: [PendingInvite] = []

    /// Outstanding invitations, from the cache, so the setup checklist can
    /// answer "has anyone been invited" offline. `pendingInvites` is the live
    /// list and is only populated on the screen that manages them.
    private(set) var pendingInviteCount: Int = 0

    /// Whether this circle has actually been shared with anyone.
    ///
    /// Being in a group is not the same thing. Creating one during onboarding
    /// makes `activeGroupID` non-nil immediately, which used to tick the
    /// "Invite the family" step for an owner who was still the only member and
    /// tell them "5 of 6 set up" while their siblings had no access at all.
    var hasSharedWithFamily: Bool {
        guard activeGroupID != nil else { return false }
        return members.filter { !$0.isSelf }.count > 0 || pendingInviteCount > 0
    }

    /// True while the member list has never successfully loaded for this group.
    /// The transparency screen needs to tell "nobody else is here" apart from
    /// "this phone has not been able to ask yet".
    var hasCachedMemberList: Bool { !members.isEmpty }

    /// What to stamp on a row this device writes, so a sibling reading it later
    /// sees a name rather than "You" for someone who is not them.
    ///
    /// Empty until `loadMembers()` has run at least once, which is why every
    /// caller supplies its own fallback rather than blocking on it: naming the
    /// author is worth having and is never worth a spinner (I1).
    var selfDisplayName: String {
        members.first(where: \.isSelf)?.displayName ?? ""
    }

    /// This account's user id, for matching against rows that name an assignee.
    /// Nil until `loadMembers()` has run at least once, which is why
    /// `TaskPlanner.isAssigned` falls back to the name rather than treating a
    /// nil here as "nothing is mine".
    var selfUserID: UUID? {
        members.first(where: \.isSelf)?.id
    }

    /// Whether anyone else is actually in this circle. The "Mine" task filter
    /// is meaningless for a solo caregiver (there is no member list, so this
    /// device has neither a user id nor a name to match on), so the control is
    /// not shown at all rather than shown and always empty.
    var hasOtherMembers: Bool {
        members.contains { !$0.isSelf }
    }

    private(set) var isWorking = false
    private(set) var lastError: String?

    /// Mirrored from the cached `CareGroup` so views can read it synchronously.
    private(set) var activeGroupID: UUID?
    private(set) var groupName: String = ""
    private(set) var role: GroupRole = .owner
    private(set) var hasPlus: Bool = false
    private(set) var requiresTransparency = false

    private let log = Logger(subsystem: "com.jackwallner.aging", category: "groups")
    private var auth: AuthService { .shared }
    private var client: SupabaseClient { auth.client }

    private var context: ModelContext { CareModelStore.sharedModelContainer.mainContext }

    private init() {}

    // MARK: Cache

    /// Reads the cached membership. Synchronous, network-free, safe before first
    /// paint, and the reason a subject's restricted UI is correct offline.
    func loadFromCache() {
        guard let group = cachedGroup() else {
            activeGroupID = nil
            groupName = ""
            hasPlus = false
            requiresTransparency = false
            members = []
            pendingInviteCount = 0
            return
        }
        activeGroupID = group.id
        groupName = group.name
        role = group.role
        hasPlus = group.hasPlus
        requiresTransparency = group.role == .subject && !hasAcceptedTransparency(for: group.id)
        pendingInviteCount = group.pendingInviteCount
        members = cachedMembers(of: group.id)
    }

    /// The saved member list, in the order the server sends it. Read at launch
    /// so `members` is populated before any request has been made.
    private func cachedMembers(of groupID: UUID) -> [GroupMember] {
        let descriptor = FetchDescriptor<CachedGroupMember>(
            predicate: #Predicate { $0.groupID == groupID },
            sortBy: [SortDescriptor(\.joinedAt)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map {
            GroupMember(
                id: $0.id,
                displayName: $0.displayName,
                role: $0.role,
                joinedAt: $0.joinedAt,
                isSelf: $0.isSelf
            )
        }
    }

    /// Replaces the cached list wholesale. A member who was removed on the
    /// server has to disappear here too, so this is a replace rather than an
    /// upsert: a stale row in a "who can see me" list is the wrong kind of
    /// wrong.
    private func cacheMembers(_ list: [GroupMember], groupID: UUID) {
        let descriptor = FetchDescriptor<CachedGroupMember>(
            predicate: #Predicate { $0.groupID == groupID }
        )
        for row in (try? context.fetch(descriptor)) ?? [] {
            context.delete(row)
        }
        for member in list {
            context.insert(CachedGroupMember(
                id: member.id,
                groupID: groupID,
                displayName: member.displayName,
                role: member.role,
                joinedAt: member.joinedAt,
                isSelf: member.isSelf
            ))
        }
        try? context.save()
    }

    private func cachedGroup() -> CareGroup? {
        var descriptor = FetchDescriptor<CareGroup>(sortBy: [SortDescriptor(\.joinedAt)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func cache(id: UUID, name: String, role: GroupRole) {
        let group = cachedGroup() ?? {
            let new = CareGroup(id: id, name: name, role: role)
            context.insert(new)
            return new
        }()
        group.id = id
        group.name = name
        group.role = role
        group.updatedAt = Date()
        try? context.save()
        loadFromCache()
    }

    // MARK: Refresh

    /// Pulls the caller's membership row and the group billing row. Failure is
    /// never escalated: the cache stays authoritative and the UI stays usable.
    func refresh() async {
        guard let userID = auth.userID else { return }

        struct MembershipRow: Decodable {
            struct GroupRow: Decodable { var id: UUID; var name: String }
            var role: String
            var joined_at: Date
            var groups: GroupRow
        }

        do {
            let rows: [MembershipRow] = try await client
                .from("group_members")
                .select("role, joined_at, groups(id, name)")
                .eq("user_id", value: userID)
                .is("removed_at", value: nil)
                .order("joined_at", ascending: true)
                .execute()
                .value

            guard let row = rows.first else {
                // Signed in but in no group. Not an error: it is the state
                // between signing in and choosing a path.
                return
            }


            if rows.count > 1 {
                lastError = "This account belongs to more than one care circle. Contact support so the records can be merged safely."
            }

            cache(
                id: row.groups.id,
                name: row.groups.name,
                role: GroupRole(rawValue: row.role) ?? .subject
            )
            await refreshBilling()
        } catch {
            log.notice("Membership refresh failed, using cache: \(error.localizedDescription)")
        }
    }

    /// The group-scoped entitlement (D30). Cached alongside membership so a
    /// sibling who is not the payer keeps Plus while offline.
    func refreshBilling() async {
        guard let groupID = activeGroupID else { return }

        struct BillingRow: Decodable {
            var entitlement: String
            var expires_at: Date?
            var is_lifetime: Bool
        }

        do {
            let rows: [BillingRow] = try await client
                .from("group_billing")
                .select("entitlement, expires_at, is_lifetime")
                .eq("group_id", value: groupID)
                .limit(1)
                .execute()
                .value

            guard let group = cachedGroup() else { return }
            if let row = rows.first {
                group.entitlement = row.entitlement
                group.entitlementExpiresAt = row.expires_at
                group.isLifetime = row.is_lifetime
            } else {
                group.entitlement = "free"
                group.entitlementExpiresAt = nil
                group.isLifetime = false
            }
            group.updatedAt = Date()
            try? context.save()
            loadFromCache()
        } catch {
            log.notice("Billing refresh failed, using cache: \(error.localizedDescription)")
        }
    }

    func loadMembers() async {
        guard let groupID = activeGroupID, let me = auth.userID else { return }

        struct MemberRow: Decodable {
            struct ProfileRow: Decodable { var display_name: String }
            var user_id: UUID
            var role: String
            var joined_at: Date
            var access_scope: String?
            var profiles: ProfileRow?
        }

        struct GrantRow: Decodable {
            var user_id: UUID
            var care_recipient_id: UUID
        }

        // Two selects, newest first. `access_scope` only exists once migration
        // 0018 has been applied, and PostgREST answers a select naming an
        // unknown column by failing the whole request: without the fallback, a
        // client that shipped ahead of the migration would show an empty family
        // rather than a family with no restrictions. Costs one extra round trip
        // exactly once, on a database that is behind.
        func fetchMembers() async throws -> [MemberRow] {
            do {
                return try await client
                    .from("group_members")
                    .select("user_id, role, joined_at, access_scope, profiles(display_name)")
                    .eq("group_id", value: groupID)
                    .is("removed_at", value: nil)
                    .order("joined_at", ascending: true)
                    .execute()
                    .value
            } catch {
                log.notice("access_scope not present, reading members without it: \(error.localizedDescription)")
                return try await client
                    .from("group_members")
                    .select("user_id, role, joined_at, profiles(display_name)")
                    .eq("group_id", value: groupID)
                    .is("removed_at", value: nil)
                    .order("joined_at", ascending: true)
                    .execute()
                    .value
            }
        }

        do {
            let rows: [MemberRow] = try await fetchMembers()

            // Fetched separately rather than as an embedded resource: the grant
            // table is empty for every circle that has never restricted anyone,
            // which is almost all of them, so this is one cheap request that
            // usually returns nothing.
            let grants: [GrantRow] = (try? await client
                .from("recipient_access")
                .select("user_id, care_recipient_id")
                .eq("group_id", value: groupID)
                .execute()
                .value) ?? []

            var grantsByUser: [UUID: Set<UUID>] = [:]
            for grant in grants {
                grantsByUser[grant.user_id, default: []].insert(grant.care_recipient_id)
            }

            members = rows.map {
                GroupMember(
                    id: $0.user_id,
                    displayName: $0.profiles?.display_name ?? "",
                    role: GroupRole(rawValue: $0.role) ?? .caregiver,
                    joinedAt: $0.joined_at,
                    isSelf: $0.user_id == me,
                    accessScope: MemberAccessScope(rawValue: $0.access_scope ?? "all"),
                    visibleRecipientIDs: grantsByUser[$0.user_id] ?? []
                )
            }
            cacheMembers(members, groupID: groupID)
            applySelfAccess(members.first { $0.isSelf }, groupID: groupID)
        } catch {
            // The cached list loaded at launch stays on screen. A failed
            // request is not evidence that the family shrank.
            log.notice("Member list failed, keeping the cached copy: \(error.localizedDescription)")
        }
    }

    func loadPendingInvites() async {
        guard let groupID = activeGroupID else {
            pendingInvites = []
            return
        }

        struct InviteRow: Decodable {
            var code: String
            var intended_email: String?
            var role_to_grant: String
            var care_recipient_id: UUID?
            var expires_at: Date
        }

        do {
            let rows: [InviteRow] = try await client
                .from("invite_codes")
                .select("code, intended_email, role_to_grant, care_recipient_id, expires_at")
                .eq("group_id", value: groupID)
                .is("used_at", value: nil)
                .is("revoked_at", value: nil)
                .order("created_at", ascending: false)
                .execute()
                .value

            pendingInvites = rows.map {
                PendingInvite(
                    code: $0.code,
                    email: $0.intended_email,
                    role: GroupRole(rawValue: $0.role_to_grant) ?? .caregiver,
                    recipientID: $0.care_recipient_id,
                    expiresAt: $0.expires_at
                )
            }
            cachePendingInviteCount(pendingInvites.filter { !$0.isExpired }.count)
        } catch {
            log.notice("Pending invite list failed: \(error.localizedDescription)")
        }
    }

    private func cachePendingInviteCount(_ count: Int) {
        pendingInviteCount = count
        guard let group = cachedGroup() else { return }
        group.pendingInviteCount = count
        try? context.save()
    }

    // MARK: Lifecycle

    /// Creates the group and adopts whatever is already on this device into it.
    ///
    /// Adoption is the ordinary write path, not a special one: the local UUIDs
    /// are already the server primary keys, so stamping the group id on and
    /// marking the rows dirty is enough, and it inherits idempotency and
    /// resumability for free (D18, §11).
    @discardableResult
    func createGroup(named name: String) async throws -> UUID {
        guard auth.isSignedIn else { throw GroupServiceError.notSignedIn }
        guard activeGroupID == nil else {
            throw GroupServiceError.server(
                "You already have a care circle. Add another person under Care instead."
            )
        }
        isWorking = true
        defer { isWorking = false }

        do {
            let groupID: UUID = try await client
                .rpc("create_group", params: ["p_name": name])
                .execute()
                .value

            cache(id: groupID, name: name, role: .owner)
            return groupID
        } catch {
            throw GroupServiceError.server(error.localizedDescription)
        }
    }

    func rename(to name: String) async throws {
        guard let groupID = activeGroupID else { throw GroupServiceError.noGroup }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try await client
                .from("groups")
                .update(["name": trimmed])
                .eq("id", value: groupID)
                .execute()
            cache(id: groupID, name: trimmed, role: role)
        } catch {
            throw GroupServiceError.server(error.localizedDescription)
        }
    }

    // MARK: Invites

    /// `recipientID` is required for a subject invite and ignored otherwise: it
    /// is what joins Mom to the profile the family already built for her instead
    /// of leaving her as an unattached member with no history.
    func generateInviteCode(
        role inviteRole: GroupRole,
        recipientID: UUID? = nil,
        email: String? = nil,
        ttlHours: Int = 48
    ) async throws -> String {
        guard let groupID = activeGroupID else { throw GroupServiceError.noGroup }
        isWorking = true
        defer { isWorking = false }

        // Every RPC parameter is text and cast to uuid inside the function, so
        // PostgREST never has to choose between a (uuid) and a (text) overload.
        var params: [String: String] = [
            "p_group_id": groupID.uuidString,
            "p_role": inviteRole == .subject ? "subject" : "caregiver",
            "p_ttl_hours": String(ttlHours)
        ]
        if let recipientID {
            params["p_care_recipient_id"] = recipientID.uuidString
        }
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let normalizedEmail, !normalizedEmail.isEmpty {
            params["p_email"] = normalizedEmail
        }

        do {
            let code: String = try await client
                .rpc("generate_invite_code", params: params)
                .execute()
                .value
            await loadPendingInvites()
            return code
        } catch {
            throw GroupServiceError.server(error.localizedDescription)
        }
    }

    /// Set which of the circle's people one member may read.
    ///
    /// Owner-only, and the server says so too: this call is a convenience for
    /// the Sharing screen, not the enforcement. Passing `.all` clears every
    /// grant that member had, so lifting a restriction is one call rather than
    /// a list the caller has to reconstruct.
    func setAccess(
        for memberID: UUID,
        scope: MemberAccessScope,
        recipientIDs: Set<UUID> = []
    ) async throws {
        guard let groupID = activeGroupID else { throw GroupServiceError.noGroup }

        // Every RPC parameter is text and cast inside (D11).
        var params: [String: AnyJSON] = [
            "p_group_id": .string(groupID.uuidString),
            "p_user_id": .string(memberID.uuidString),
            "p_scope": .string(scope.rawValue)
        ]
        params["p_recipient_ids"] = scope == .listed
            ? .array(recipientIDs.map { .string($0.uuidString) })
            : .null

        do {
            try await client.rpc("set_member_access", params: params).execute()
            await loadMembers()
        } catch {
            throw GroupServiceError.server(error.localizedDescription)
        }
    }

    func revokeInviteCode(_ code: String) async throws {
        do {
            try await client
                .rpc("revoke_invite_code", params: ["p_code": code])
                .execute()
            await loadPendingInvites()
        } catch {
            throw GroupServiceError.server(error.localizedDescription)
        }
    }

    @discardableResult
    func acceptInvite(code: String) async throws -> UUID {
        guard auth.isSignedIn else { throw GroupServiceError.notSignedIn }
        isWorking = true
        defer { isWorking = false }

        struct AcceptRow: Decodable {
            var ok: Bool
            var joined_group_id: UUID?
            var error_code: String?
        }

        let normalized = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let rows: [AcceptRow] = try await client
                .rpc("accept_invite", params: ["p_code": normalized])
                .execute()
                .value

            guard let row = rows.first else {
                throw GroupServiceError.invite(.invalidCode)
            }
            guard row.ok, let groupID = row.joined_group_id else {
                throw GroupServiceError.invite(
                    InviteFailure(rawValue: row.error_code ?? "") ?? .invalidCode
                )
            }

            await refresh()
            return groupID
        } catch let error as GroupServiceError {
            throw error
        } catch {
            throw GroupServiceError.server(error.localizedDescription)
        }
    }

    func markTransparencyAccepted() {
        guard let activeGroupID else { return }
        UserDefaults.standard.set(true, forKey: transparencyKey(for: activeGroupID))
        requiresTransparency = false
    }

    // MARK: Membership mutations

    func changeRole(of userID: UUID, to newRole: GroupRole) async throws {
        guard let groupID = activeGroupID else { throw GroupServiceError.noGroup }
        try await call("change_role", [
            "p_group_id": groupID.uuidString,
            "p_user_id": userID.uuidString,
            "p_role": newRole.rawValue
        ])
        await loadMembers()
    }

    func removeMember(_ userID: UUID) async throws {
        guard let groupID = activeGroupID else { throw GroupServiceError.noGroup }
        try await call("remove_member", [
            "p_group_id": groupID.uuidString,
            "p_user_id": userID.uuidString
        ])
        await loadMembers()
    }

    func transferOwnership(to userID: UUID) async throws {
        guard let groupID = activeGroupID else { throw GroupServiceError.noGroup }
        try await call("transfer_ownership", [
            "p_group_id": groupID.uuidString,
            "p_new_owner_id": userID.uuidString
        ])
        await refresh()
        await loadMembers()
    }

    /// The subject can always call this (D27). Leaving is not blocked, because
    /// an app a parent cannot walk away from is a surveillance tool their
    /// children installed on them. The safety net is that the group is told.
    func leaveGroup() async throws {
        guard let groupID = activeGroupID else { throw GroupServiceError.noGroup }
        try await call("leave_group", ["p_group_id": groupID.uuidString])
        forgetGroupLocally()
    }

    func deleteGroup() async throws {
        guard let groupID = activeGroupID else { throw GroupServiceError.noGroup }
        try await call("delete_group", ["p_group_id": groupID.uuidString])
        forgetGroupLocally()
    }

    /// Drops the membership cache and the shared record, leaving the device with
    /// nothing it is no longer entitled to hold.
    /// What this device is allowed to see, once the owner has narrowed it.
    ///
    /// Nil means unrestricted, which is every member of every circle until
    /// somebody deliberately changes it.
    private(set) var selfVisibleRecipientIDs: Set<UUID>?

    /// Keep the local mirror inside the boundary the server is now enforcing.
    ///
    /// Restricting a member stops the server *returning* rows for the people
    /// they can no longer see, but the pull is incremental: absence from a page
    /// is not a delete signal, so anything already synced would sit on their
    /// phone indefinitely, readable offline, after their access was removed.
    /// A restriction that only applies to rows you have not downloaded yet is
    /// not a restriction.
    ///
    /// `context.delete`, never `tombstone()`. This is the same local forget
    /// `forgetGroupLocally` performs and for the same reason: a tombstone is a
    /// synced instruction to destroy the row for the whole family, and losing
    /// your access to Dad's record must never delete Dad's record (I5).
    private func applySelfAccess(_ me: GroupMember?, groupID: UUID) {
        let previous = selfVisibleRecipientIDs
        let current: Set<UUID>? = me?.accessScope == .listed ? (me?.visibleRecipientIDs ?? []) : nil
        selfVisibleRecipientIDs = current

        guard previous != current else { return }

        if let current {
            for person in ((try? context.fetch(FetchDescriptor<Person>())) ?? [])
            where person.groupID == groupID && !current.contains(person.id) {
                // Local-only records are never touched: a private record that
                // was never in the circle is not the circle's to withdraw.
                context.delete(person)
            }
        }

        // The pull cursor is a high-water mark on `updated_at`, so rows that
        // existed before a restriction was lifted would never be re-fetched.
        // Resetting it makes the next sync re-read the circle from the start,
        // which is cheap at family scale and correct in both directions.
        for cursor in (try? context.fetch(FetchDescriptor<SyncCursor>())) ?? [] {
            context.delete(cursor)
        }
        try? context.save()
    }

    func forgetGroupLocally() {
        if let activeGroupID {
            UserDefaults.standard.removeObject(forKey: transparencyKey(for: activeGroupID))
        }
        if let group = cachedGroup() { context.delete(group) }
        for member in (try? context.fetch(FetchDescriptor<CachedGroupMember>())) ?? [] {
            context.delete(member)
        }
        for person in ((try? context.fetch(FetchDescriptor<Person>())) ?? [])
        where person.groupID != nil {
            context.delete(person)
        }
        for cursor in (try? context.fetch(FetchDescriptor<SyncCursor>())) ?? [] {
            context.delete(cursor)
        }
        for entry in (try? context.fetch(FetchDescriptor<OutboxEntry>())) ?? [] {
            context.delete(entry)
        }
        try? context.save()
        members = []
        pendingInvites = []
        pendingInviteCount = 0
        loadFromCache()
    }

    private func hasAcceptedTransparency(for groupID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: transparencyKey(for: groupID))
    }

    private func transparencyKey(for groupID: UUID) -> String {
        "acceptedTransparency.\(groupID.uuidString)"
    }

    private func call(_ name: String, _ params: [String: String]) async throws {
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.rpc(name, params: params).execute()
        } catch {
            throw GroupServiceError.server(error.localizedDescription)
        }
    }
}
