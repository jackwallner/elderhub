package com.jackwallner.aging

import android.app.Activity
import com.jackwallner.aging.data.AccessScope
import com.jackwallner.aging.data.AuthBackend
import com.jackwallner.aging.data.Billing
import com.jackwallner.aging.data.Cloud
import com.jackwallner.aging.data.GroupBackend
import com.jackwallner.aging.data.GroupRole
import com.jackwallner.aging.data.IdTokenSource
import com.jackwallner.aging.data.Membership
import com.jackwallner.aging.data.MemberRow
import com.jackwallner.aging.data.PendingInvite
import com.jackwallner.aging.data.ProviderCredential
import com.jackwallner.aging.data.Session
import com.jackwallner.aging.data.SupabaseError
import com.jackwallner.aging.data.SyncFailure
import com.jackwallner.aging.data.SyncRemote
import com.jackwallner.aging.data.SyncWire
import com.jackwallner.aging.model.SyncEntity
import com.jackwallner.aging.model.SyncPage
import java.time.Instant
import java.util.UUID
import org.json.JSONObject

/**
 * Debug-only stand-in for Supabase: auth, the circle RPCs and the sync tables,
 * in memory, with the same rules the migrations enforce where a test depends
 * on them (one circle per account, staff-only invites, owner-only role changes,
 * server-owned `updated_at`, per-recipient access). Never compiled into a
 * release or QA build, and it holds no secret: the "Google" sign-in it offers
 * signs in a made-up account.
 */
class FakeCareServer(private val clock: () -> Instant = Instant::now) : AuthBackend, GroupBackend, SyncRemote, IdTokenSource {
    data class User(val id: UUID, var name: String)
    data class Member(val groupId: UUID, val userId: UUID, var role: GroupRole, val joinedAt: Instant, var scope: AccessScope = AccessScope.ALL, var removed: Boolean = false)
    data class Invite(val code: String, val groupId: UUID, val role: GroupRole, val recipientId: UUID?, val email: String?, val expiresAt: Instant, var used: Boolean = false, var revoked: Boolean = false)

    val users = mutableMapOf<UUID, User>()
    val groupNames = mutableMapOf<UUID, String>()
    val members = mutableListOf<Member>()
    val grants = mutableSetOf<Pair<UUID, UUID>>()
    val invites = mutableListOf<Invite>()
    val billingRows = mutableMapOf<UUID, Billing>()
    val tables = SyncEntity.entries.associateWith { linkedMapOf<UUID, JSONObject>() }

    /** The account the fake "Google" button signs in. */
    var signInAs = User(UUID.fromString("00000000-0000-4000-8000-00000000a001"), "Jack Wallner")
    override var session: Session? = null
        private set
    var isOnline = true
    private var tick = 0L

    private val me: UUID get() = session?.userId?.let(UUID::fromString) ?: throw SupabaseError.NotSignedIn

    private fun now(): Instant = clock().plusNanos(1_000 * ++tick)

    private fun online() {
        if (!isOnline) throw java.io.IOException("offline")
    }

    fun cloud() = Cloud(this, this, this, this, isFake = true)

    // MARK: Auth

    override val isAvailable: Boolean get() = true

    override suspend fun request(activity: Activity) = ProviderCredential("google", "fake-id-token", "fake-nonce", signInAs.name)

    override suspend fun signInWithIdToken(provider: String, idToken: String, rawNonce: String?): Session {
        online()
        val user = users.getOrPut(signInAs.id) { User(signInAs.id, "") }
        return Session("fake-access", "fake-refresh", Long.MAX_VALUE, user.id.toString(), user.name).also { session = it }
    }

    override suspend fun refresh(): Session {
        online()
        return session ?: throw SupabaseError.SessionRevoked
    }

    override suspend fun signOut() { session = null }

    override fun forgetSession() { session = null }

    override fun rememberDisplayName(name: String) {
        session = session?.copy(displayName = name)
    }

    // MARK: Groups

    private fun membership(groupId: UUID, userId: UUID = me) = members.firstOrNull { it.groupId == groupId && it.userId == userId && !it.removed }

    private fun requireStaff(groupId: UUID) {
        if (membership(groupId)?.role?.isStaff != true) throw SupabaseError.Http(403, "42501", "not authorized")
    }

    private fun requireOwner(groupId: UUID) {
        if (membership(groupId)?.role != GroupRole.OWNER) throw SupabaseError.Http(403, "42501", "only an owner can do that")
    }

    override suspend fun memberships(userId: UUID): List<Membership> {
        online()
        return members.filter { it.userId == userId && !it.removed }.sortedBy { it.joinedAt }
            .map { Membership(it.groupId, groupNames[it.groupId].orEmpty(), it.role, it.joinedAt) }
    }

    override suspend fun billing(groupId: UUID): Billing? { online(); return billingRows[groupId] }

    override suspend fun members(groupId: UUID): List<MemberRow> {
        online()
        if (membership(groupId) == null) return emptyList()
        return members.filter { it.groupId == groupId && !it.removed }.sortedBy { it.joinedAt }
            .map { MemberRow(it.userId, it.role, it.joinedAt, it.scope, users[it.userId]?.name.orEmpty()) }
    }

    override suspend fun grants(groupId: UUID): List<Pair<UUID, UUID>> {
        online()
        return grants.filter { (user, recipient) -> members.any { it.userId == user && it.groupId == groupId } && tables.getValue(SyncEntity.PERSON)[recipient] != null }
    }

    override suspend fun pendingInvites(groupId: UUID): List<PendingInvite> {
        online()
        requireStaff(groupId)
        return invites.filter { it.groupId == groupId && !it.used && !it.revoked }.reversed()
            .map { PendingInvite(it.code, it.email, it.role, it.recipientId, it.expiresAt) }
    }

    override suspend fun createGroup(name: String): UUID {
        online()
        if (members.any { it.userId == me && !it.removed }) throw SupabaseError.Http(400, "P0001", "already in a care circle")
        val id = UUID.randomUUID()
        groupNames[id] = name
        members += Member(id, me, GroupRole.OWNER, now())
        return id
    }

    override suspend fun renameGroup(groupId: UUID, name: String) {
        online(); requireOwner(groupId); groupNames[groupId] = name
    }

    override suspend fun generateInvite(groupId: UUID, role: GroupRole, recipientId: UUID?, email: String?, ttlHours: Int): String {
        online(); requireStaff(groupId)
        val alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
        val code = (1..8).map { alphabet[(invites.size * 7 + it * 13 + tick.toInt()) % alphabet.length] }.joinToString("")
        invites += Invite(code, groupId, role, recipientId, email, clock().plusSeconds(ttlHours * 3600L))
        return code
    }

    override suspend fun revokeInvite(code: String) {
        online()
        invites.firstOrNull { it.code == code }?.let { requireStaff(it.groupId); it.revoked = true }
    }

    /** Includes 0019/0020: an untouched solo circle of the caller's own is closed so they can join. */
    override suspend fun acceptInvite(code: String): Triple<Boolean, UUID?, String?> {
        online()
        val invite = invites.firstOrNull { it.code == code && !it.used && !it.revoked && it.expiresAt.isAfter(clock()) }
            ?: return Triple(false, null, "invalid_code")
        val existing = members.firstOrNull { it.userId == me && !it.removed }
        if (existing != null) {
            val solo = members.count { it.groupId == existing.groupId && !it.removed } == 1 && existing.role == GroupRole.OWNER
            val untouched = tables.filterKeys { it != SyncEntity.PERSON }.values.none { rows -> rows.values.any { it.optString("group_id") == existing.groupId.toString() } }
            if (!solo || !untouched) return Triple(false, null, "already_in_group")
            existing.removed = true
        }
        invite.used = true
        members += Member(invite.groupId, me, invite.role, now())
        if (invite.role == GroupRole.SUBJECT && invite.recipientId != null) {
            tables.getValue(SyncEntity.PERSON)[invite.recipientId]?.let { touch(SyncEntity.PERSON, it.put("linked_user_id", me.toString())) }
        }
        return Triple(true, invite.groupId, null)
    }

    override suspend fun setMemberAccess(groupId: UUID, userId: UUID, scope: AccessScope, recipientIds: Set<UUID>) {
        online(); requireOwner(groupId)
        val member = membership(groupId, userId) ?: throw SupabaseError.Http(400, "22023", "member not found")
        if (member.role == GroupRole.OWNER) throw SupabaseError.Http(400, "22023", "an organizer cannot be restricted")
        member.scope = scope
        grants.removeAll { it.first == userId }
        if (scope == AccessScope.LISTED) recipientIds.forEach { grants += userId to it }
    }

    override suspend fun changeRole(groupId: UUID, userId: UUID, role: GroupRole) {
        online(); requireOwner(groupId)
        (membership(groupId, userId) ?: throw SupabaseError.Http(400, "22023", "member not found")).role = role
    }

    override suspend fun removeMember(groupId: UUID, userId: UUID) {
        online(); requireOwner(groupId)
        (membership(groupId, userId) ?: throw SupabaseError.Http(400, "22023", "member not found")).removed = true
    }

    override suspend fun transferOwnership(groupId: UUID, userId: UUID) {
        online(); requireOwner(groupId)
        val target = membership(groupId, userId) ?: throw SupabaseError.Http(400, "22023", "member not found")
        membership(groupId)!!.role = GroupRole.CAREGIVER
        target.role = GroupRole.OWNER
    }

    override suspend fun leaveGroup(groupId: UUID) {
        online()
        val mine = membership(groupId) ?: throw SupabaseError.Http(400, "22023", "not a member")
        val others = members.count { it.groupId == groupId && !it.removed && it.userId != me }
        if (mine.role == GroupRole.OWNER && others > 0) throw SupabaseError.Http(400, "23514", "transfer ownership before leaving")
        mine.removed = true
    }

    override suspend fun deleteGroup(groupId: UUID) {
        online(); requireOwner(groupId)
        members.filter { it.groupId == groupId }.forEach { it.removed = true }
        tables.values.forEach { rows -> rows.values.removeAll { it.optString("group_id") == groupId.toString() } }
    }

    override suspend fun updateDisplayName(userId: UUID, name: String) {
        online(); users[userId]?.name = name
    }

    override suspend fun deleteAccount() {
        online()
        members.filter { it.userId == me }.forEach { it.removed = true }
        users.remove(me)
    }

    // MARK: Sync tables

    private fun visible(groupId: UUID, row: JSONObject, entity: SyncEntity): Boolean {
        val mine = membership(groupId) ?: return false
        if (mine.scope != AccessScope.LISTED || mine.role == GroupRole.OWNER) return true
        val recipient = when (entity) {
            SyncEntity.PERSON -> SyncWire.run { row.uuid("id") }
            SyncEntity.DOSE_LOG -> tables.getValue(SyncEntity.MEDICATION)[UUID.fromString(row.getString("medication_id"))]
                ?.optString("care_recipient_id")?.let(UUID::fromString)
            else -> UUID.fromString(row.getString("care_recipient_id"))
        }
        return recipient != null && (me to recipient) in grants
    }

    override suspend fun pull(entity: SyncEntity, groupId: UUID, after: SyncPage?, limit: Int): List<JSONObject> {
        if (!isOnline) throw SyncFailure.Offline
        return tables.getValue(entity).values
            .filter { it.optString("group_id") == groupId.toString() && visible(groupId, it, entity) }
            .map { JSONObject(it.toString()) }
            .sortedWith(compareBy({ SyncWire.instant(it.getString("updated_at")) }, { it.getString("id") }))
            .filter { row ->
                if (after == null) return@filter true
                val t = SyncWire.instant(row.getString("updated_at"))!!
                t > after.updatedAt || (t == after.updatedAt && row.getString("id") > after.id.toString())
            }
            .take(limit)
    }

    override suspend fun push(entity: SyncEntity, row: JSONObject) {
        if (!isOnline) throw SyncFailure.Offline
        val groupId = UUID.fromString(row.getString("group_id"))
        val role = membership(groupId)?.role
        if (role == null || (!role.isStaff && entity != SyncEntity.DOSE_LOG)) throw SyncFailure.Rejected("new row violates row-level security policy")
        val id = UUID.fromString(row.getString("id"))
        val merged = tables.getValue(entity)[id]?.let { existing -> JSONObject(existing.toString()).also { e -> row.keys().forEach { e.put(it, row.get(it)) } } } ?: row
        touch(entity, merged)
    }

    /** Server-owned `updated_at`, as `touch_updated_at` does. */
    fun touch(entity: SyncEntity, row: JSONObject): JSONObject {
        row.put("updated_at", now().toString())
        if (!row.has("deleted_at")) row.put("deleted_at", JSONObject.NULL)
        tables.getValue(entity)[UUID.fromString(row.getString("id"))] = row
        return row
    }

    // MARK: Seeding for screenshots and device tests

    /**
     * A circle somebody else already runs: Sarah organises Eleanor's record and
     * has sent an invitation the signed-in account can accept.
     */
    fun seedSarahsCircle(): String {
        val sarah = User(UUID.fromString("00000000-0000-4000-8000-00000000b002"), "Sarah Wallner")
        users[sarah.id] = sarah
        val groupId = UUID.fromString("00000000-0000-4000-8000-0000000c0003")
        groupNames[groupId] = "Eleanor's care circle"
        members += Member(groupId, sarah.id, GroupRole.OWNER, clock().minusSeconds(86_400 * 30))
        val momId = UUID.fromString("00000000-0000-4000-8000-0000000d0004")
        touch(SyncEntity.PERSON, JSONObject().put("id", momId.toString()).put("group_id", groupId.toString()).put("name", "Eleanor Wallner")
            .put("relationship", "Mom").put("blood_type", "A+").put("color_index", 0).put("allergies", org.json.JSONArray(listOf("Penicillin")))
            .put("conditions", org.json.JSONArray(listOf("Hypertension"))).put("notes", "")
            .put("last_check_in_at", clock().minusSeconds(3 * 3600).toString()))
        touch(SyncEntity.MEDICATION, JSONObject().put("id", "00000000-0000-4000-8000-0000000e0005").put("group_id", groupId.toString())
            .put("care_recipient_id", momId.toString()).put("name", "Lisinopril").put("strength", "10 mg").put("form", "tablet")
            .put("purpose", "Blood pressure").put("prescriber", "").put("pharmacy", "").put("instructions", "With breakfast")
            .put("schedule_minutes", org.json.JSONArray(listOf(480))).put("weekdays", org.json.JSONArray(emptyList<Int>()))
            .put("is_as_needed", false).put("is_active", true).put("start_date", clock().minusSeconds(86_400 * 60).toString())
            .put("tracks_refills", false).put("quantity_remaining", 0).put("units_per_dose", 1).put("refill_threshold_days", 7))
        val code = "HKT7PQ2M"
        invites += Invite(code, groupId, GroupRole.CAREGIVER, null, null, clock().plusSeconds(48 * 3600))
        return code
    }

    /** Adds a sibling to the signed-in account's own circle, so member screens have someone to show. */
    fun addSibling(groupId: UUID, name: String = "Michael Wallner"): UUID {
        val sibling = User(UUID.fromString("00000000-0000-4000-8000-00000000f006"), name)
        users[sibling.id] = sibling
        members += Member(groupId, sibling.id, GroupRole.CAREGIVER, now())
        return sibling.id
    }

    /** Another family member edits a row on their phone. */
    fun editAsFamily(entity: SyncEntity, id: UUID, change: (JSONObject) -> Unit) {
        val row = tables.getValue(entity)[id] ?: return
        change(row)
        touch(entity, row)
    }

    companion object {
        /** One per process, so a relaunched activity in a device test sees the same "server". */
        val shared by lazy { FakeCareServer() }
    }
}
