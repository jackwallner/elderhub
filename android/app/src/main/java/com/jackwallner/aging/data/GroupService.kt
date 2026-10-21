package com.jackwallner.aging.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jackwallner.aging.model.SyncEntity
import com.jackwallner.aging.model.SyncState
import java.time.Instant
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/**
 * Who is in this family and what they may do, port of `GroupService.swift`.
 *
 * Membership, role and the circle's Plus entitlement are cached on the phone
 * and every read prefers the cache: role gating has to work with the network
 * down. Every mutation is an RPC; the UI mirrors the RLS policies and is never
 * the enforcement.
 */
class GroupService(
    private val values: KeyValueStore,
    private val care: CareStore,
    private val auth: AuthService,
    private val cloud: () -> Cloud,
    private val clock: () -> Instant = Instant::now,
) {
    var activeGroupId by mutableStateOf<UUID?>(null)
        private set
    var groupName by mutableStateOf("")
        private set
    var role by mutableStateOf(GroupRole.OWNER)
        private set
    var hasPlus by mutableStateOf(false)
        private set
    var requiresTransparency by mutableStateOf(false)
        private set
    var members by mutableStateOf<List<GroupMember>>(emptyList())
        private set
    var pendingInvites by mutableStateOf<List<PendingInvite>>(emptyList())
        private set
    var pendingInviteCount by mutableIntStateOf(0)
        private set
    var lastError by mutableStateOf<String?>(null)
        private set
    var isWorking by mutableStateOf(false)
        private set

    private val backend: GroupBackend get() = cloud().groups

    /** Shared with anyone yet: being in a circle alone is not the same thing. */
    val hasSharedWithFamily: Boolean get() = activeGroupId != null && (members.any { !it.isSelf } || pendingInviteCount > 0)

    val selfDisplayName: String get() = members.firstOrNull { it.isSelf }?.displayName.orEmpty()

    // MARK: Cache

    /** Network-free, safe before first paint. */
    fun loadFromCache() {
        val id = values.getString(KEY_ID)?.let { runCatching { UUID.fromString(it) }.getOrNull() }
        activeGroupId = id
        care.circleId = id
        if (id == null) {
            groupName = ""
            role = GroupRole.OWNER
            hasPlus = false
            requiresTransparency = false
            members = emptyList()
            pendingInviteCount = 0
            return
        }
        groupName = values.getString(KEY_NAME).orEmpty()
        role = GroupRole.of(values.getString(KEY_ROLE), GroupRole.SUBJECT)
        hasPlus = computeHasPlus()
        requiresTransparency = role == GroupRole.SUBJECT && !values.getBoolean(transparencyKey(id))
        pendingInviteCount = values.getInt(KEY_INVITES)
        members = decodeMembers(values.getString(KEY_MEMBERS))
    }

    /** Deliberately ignores check-ins: the check-in path has no billing check at any depth. */
    private fun computeHasPlus(): Boolean {
        if (values.getString(KEY_ENTITLEMENT) != "plus") return false
        if (values.getBoolean(KEY_LIFETIME)) return true
        val expires = values.getString(KEY_EXPIRES)?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: return false
        return expires.isAfter(clock())
    }

    private fun cache(id: UUID, name: String, role: GroupRole) {
        values.putString(KEY_ID, id.toString())
        values.putString(KEY_NAME, name)
        values.putString(KEY_ROLE, role.raw)
        loadFromCache()
    }

    // MARK: Refresh

    /** Membership and billing. Failure is never escalated: the cache stays authoritative. */
    suspend fun refresh() {
        val userId = auth.userId ?: return
        try {
            val rows = backend.memberships(userId)
            val row = rows.firstOrNull() ?: return
            if (rows.size > 1) {
                lastError = "This account belongs to more than one care circle. Contact support so the records can be merged safely."
            }
            cache(row.groupId, row.name, row.role)
            refreshBilling()
        } catch (e: Exception) {
            // Offline or refused: keep what is cached.
        }
    }

    /** The group-scoped entitlement, so a sibling who did not pay keeps Plus offline. */
    suspend fun refreshBilling() {
        val id = activeGroupId ?: return
        try {
            val billing = backend.billing(id)
            values.putString(KEY_ENTITLEMENT, billing?.entitlement ?: "free")
            billing?.expiresAt?.let { values.putString(KEY_EXPIRES, it.toString()) } ?: values.remove(KEY_EXPIRES)
            values.putBoolean(KEY_LIFETIME, billing?.isLifetime ?: false)
            hasPlus = computeHasPlus()
        } catch (e: Exception) {
            // Cached value stands.
        }
    }

    suspend fun loadMembers() {
        val id = activeGroupId ?: return
        val me = auth.userId ?: return
        try {
            val rows = backend.members(id)
            // Empty for almost every circle; never worth failing the member list over.
            val grants = runCatching { backend.grants(id) }.getOrDefault(emptyList())
            val byUser = grants.groupBy({ it.first }, { it.second }).mapValues { it.value.toSet() }
            members = rows.map {
                GroupMember(it.userId, it.displayName, it.role, it.joinedAt, it.userId == me, it.accessScope, byUser[it.userId].orEmpty())
            }
            values.putString(KEY_MEMBERS, encodeMembers(members))
            applySelfAccess(members.firstOrNull { it.isSelf }, id)
        } catch (e: Exception) {
            // A failed request is not evidence that the family shrank.
        }
    }

    suspend fun loadPendingInvites() {
        val id = activeGroupId ?: run { pendingInvites = emptyList(); return }
        try {
            pendingInvites = backend.pendingInvites(id)
            pendingInviteCount = pendingInvites.count { !it.isExpired(clock()) }
            values.putInt(KEY_INVITES, pendingInviteCount)
        } catch (e: Exception) {
            // Keep the last list.
        }
    }

    // MARK: Lifecycle

    /**
     * Creates the circle and moves what is already on this phone into it. Only
     * the "start a care circle" path does this; joining someone else's adopts
     * nothing.
     */
    suspend fun createGroup(name: String): UUID {
        if (!auth.isSignedIn) throw GroupError("Sign in first.")
        if (activeGroupId != null) throw GroupError("You already have a care circle. Add another person under Care instead.")
        return working {
            val id = backend.createGroup(name)
            cache(id, name, GroupRole.OWNER)
            care.state.people.filter { it.groupId == null }.forEach { care.adoptPerson(it.id, id) }
            id
        }
    }

    suspend fun rename(name: String) {
        val id = activeGroupId ?: throw GroupError("You are not in a care circle yet.")
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        working { backend.renameGroup(id, trimmed) }
        cache(id, trimmed, role)
    }

    /** [recipientId] links a "person being looked after" invitation to the record the family built. */
    suspend fun generateInviteCode(role: GroupRole, recipientId: UUID?, email: String?, ttlHours: Int = 48): String {
        val id = activeGroupId ?: throw GroupError("You are not in a care circle yet.")
        val normalized = email?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
        val code = working { backend.generateInvite(id, role, if (role == GroupRole.SUBJECT) recipientId else null, normalized, ttlHours) }
        loadPendingInvites()
        return code
    }

    suspend fun revokeInviteCode(code: String) {
        working { backend.revokeInvite(code) }
        loadPendingInvites()
    }

    suspend fun acceptInvite(code: String): UUID {
        if (!auth.isSignedIn) throw GroupError("Sign in first.")
        val normalized = InviteLink.normalized(code) ?: throw GroupError(InviteFailure.INVALID_CODE.message)
        val (ok, groupId, error) = working { backend.acceptInvite(normalized) }
        if (!ok || groupId == null) throw GroupError(InviteFailure.of(error).message)
        refresh()
        loadMembers()
        return groupId
    }

    suspend fun setAccess(memberId: UUID, scope: AccessScope, recipientIds: Set<UUID>) {
        val id = activeGroupId ?: throw GroupError("You are not in a care circle yet.")
        working { backend.setMemberAccess(id, memberId, scope, recipientIds) }
        loadMembers()
    }

    suspend fun changeRole(memberId: UUID, newRole: GroupRole) {
        val id = activeGroupId ?: throw GroupError("You are not in a care circle yet.")
        working { backend.changeRole(id, memberId, newRole) }
        loadMembers()
    }

    suspend fun removeMember(memberId: UUID) {
        val id = activeGroupId ?: throw GroupError("You are not in a care circle yet.")
        working { backend.removeMember(id, memberId) }
        loadMembers()
    }

    suspend fun transferOwnership(memberId: UUID) {
        val id = activeGroupId ?: throw GroupError("You are not in a care circle yet.")
        working { backend.transferOwnership(id, memberId) }
        refresh()
        loadMembers()
    }

    /** Never blocked for the person being looked after: an app a parent cannot leave is surveillance. */
    suspend fun leaveGroup() {
        val id = activeGroupId ?: throw GroupError("You are not in a care circle yet.")
        working { backend.leaveGroup(id) }
        forgetGroupLocally()
    }

    suspend fun deleteGroup() {
        val id = activeGroupId ?: throw GroupError("You are not in a care circle yet.")
        working { backend.deleteGroup(id) }
        forgetGroupLocally()
    }

    fun markTransparencyAccepted() {
        val id = activeGroupId ?: return
        values.putBoolean(transparencyKey(id), true)
        requiresTransparency = false
    }

    /**
     * Keeps the phone inside the boundary the server now enforces. A restricted
     * member's pull no longer returns the other people, but absence from a page
     * is not a delete, so what was already downloaded is removed here, locally,
     * and **never** queued as a delete: losing access to Dad's record must not
     * delete Dad's record (I5). Every cursor rewinds so a lifted restriction
     * brings the rows back.
     */
    private fun applySelfAccess(me: GroupMember?, groupId: UUID) {
        val current: Set<UUID>? = if (me?.accessScope == AccessScope.LISTED) me.visibleRecipientIds else null
        val previous: Set<UUID>? = if (values.getBoolean(KEY_SCOPED)) values.getStringSet(KEY_VISIBLE).map(UUID::fromString).toSet() else null
        if (current == previous) return
        if (current == null) values.remove(KEY_SCOPED) else values.putBoolean(KEY_SCOPED, true)
        values.putStringSet(KEY_VISIBLE, current.orEmpty().map(UUID::toString).toSet())
        care.applyRemote { s ->
            var next = s
            if (current != null) {
                for (person in s.people.filter { it.groupId == groupId && it.id !in current }) {
                    next = removeLocally(next, SyncEntity.PERSON, person.id)
                }
            }
            next.copy(sync = next.sync.copy(cursors = emptyMap()))
        }
    }

    /**
     * Drops the membership cache and the shared record, leaving the phone with
     * nothing it is no longer entitled to hold. A wipe, not a delete: nothing
     * is queued for the family. Records that only ever lived here stay.
     */
    fun forgetGroupLocally() {
        activeGroupId?.let { values.remove(transparencyKey(it)) }
        listOf(KEY_ID, KEY_NAME, KEY_ROLE, KEY_ENTITLEMENT, KEY_EXPIRES, KEY_LIFETIME, KEY_INVITES, KEY_MEMBERS, KEY_SCOPED, KEY_VISIBLE)
            .forEach(values::remove)
        care.applyRemote { s ->
            var next = s
            for (person in s.people.filter { it.groupId != null }) {
                next = removeLocally(next, SyncEntity.PERSON, person.id)
            }
            val kept = next.people.map { it.id } + next.medications.map { it.id } + next.doses.map { it.id } +
                next.visits.map { it.id } + next.contacts.map { it.id } + next.providers.map { it.id }
            next.copy(sync = SyncState(meta = next.sync.meta.filterKeys { it in kept.toSet() }))
        }
        pendingInvites = emptyList()
        loadFromCache()
    }

    private suspend fun <T> working(block: suspend () -> T): T {
        isWorking = true
        try {
            return block()
        } catch (e: GroupError) {
            throw e
        } catch (e: SupabaseError.Http) {
            throw GroupError(e.message ?: "The server refused the change.")
        } catch (e: java.io.IOException) {
            throw GroupError("No connection. Try again when you have signal.")
        } finally {
            isWorking = false
        }
    }

    private fun transparencyKey(id: UUID) = "acceptedTransparency.$id"

    private fun encodeMembers(list: List<GroupMember>): String = JSONArray(list.map {
        JSONObject().put("id", it.id.toString()).put("name", it.displayName).put("role", it.role.raw)
            .put("joined_at", it.joinedAt.toString()).put("self", it.isSelf).put("scope", it.accessScope.raw)
            .put("visible", JSONArray(it.visibleRecipientIds.map(UUID::toString)))
    }).toString()

    private fun decodeMembers(raw: String?): List<GroupMember> {
        if (raw.isNullOrEmpty()) return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                val visible = o.optJSONArray("visible") ?: JSONArray()
                GroupMember(
                    UUID.fromString(o.getString("id")), o.optString("name"), GroupRole.of(o.optString("role"), GroupRole.CAREGIVER),
                    Instant.parse(o.getString("joined_at")), o.optBoolean("self"), AccessScope.of(o.optString("scope")),
                    (0 until visible.length()).map { UUID.fromString(visible.getString(it)) }.toSet(),
                )
            }
        }.getOrDefault(emptyList())
    }

    companion object {
        private const val KEY_ID = "group.id"
        private const val KEY_NAME = "group.name"
        private const val KEY_ROLE = "group.role"
        private const val KEY_ENTITLEMENT = "group.entitlement"
        private const val KEY_EXPIRES = "group.expiresAt"
        private const val KEY_LIFETIME = "group.isLifetime"
        private const val KEY_INVITES = "group.pendingInviteCount"
        private const val KEY_MEMBERS = "group.members"
        private const val KEY_SCOPED = "group.selfScoped"
        private const val KEY_VISIBLE = "group.selfVisible"
    }
}
