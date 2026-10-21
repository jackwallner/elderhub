package com.jackwallner.aging.data

import com.jackwallner.aging.data.SyncWire.textOrNull
import com.jackwallner.aging.data.SyncWire.uuid
import com.jackwallner.aging.data.SyncWire.uuidOrNull
import java.io.IOException
import java.time.Instant
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

enum class GroupRole(val raw: String, val label: String) {
    OWNER("owner", "Organizer"), CAREGIVER("caregiver", "Caregiver"), SUBJECT("subject", "Being supported");

    /** The line the database draws: owner and caregiver share every read and write. */
    val isStaff: Boolean get() = this != SUBJECT

    companion object {
        fun of(raw: String?, fallback: GroupRole) = entries.firstOrNull { it.raw == raw } ?: fallback
    }
}

/** Whether a member sees the whole circle or a named list of it (migration 0018). Unknown reads as `all`. */
enum class AccessScope(val raw: String) {
    ALL("all"), LISTED("listed");

    companion object {
        fun of(raw: String?) = if (raw == "listed") LISTED else ALL
    }
}

data class GroupMember(
    val id: UUID,
    val displayName: String,
    val role: GroupRole,
    val joinedAt: Instant,
    val isSelf: Boolean,
    val accessScope: AccessScope = AccessScope.ALL,
    val visibleRecipientIds: Set<UUID> = emptySet(),
) {
    /** Owners are never restrictable; the RPC refuses, so the UI does not offer it. */
    val canBeRestricted: Boolean get() = role == GroupRole.CAREGIVER

    val resolvedName: String
        get() = if (isSelf) (if (displayName.isEmpty()) "You" else "$displayName (you)") else displayName.ifEmpty { "Family member" }
}

data class PendingInvite(
    val code: String,
    val email: String?,
    val role: GroupRole,
    val recipientId: UUID?,
    val expiresAt: Instant,
) {
    fun isExpired(now: Instant = Instant.now()) = !expiresAt.isAfter(now)
}

data class Membership(val groupId: UUID, val name: String, val role: GroupRole, val joinedAt: Instant)

data class Billing(val entitlement: String, val expiresAt: Instant?, val isLifetime: Boolean)

/** Returned as values, not raised, because a raise would roll back the rate-limit row (`accept_invite`, 0004). */
enum class InviteFailure(val raw: String, val message: String) {
    INVALID_CODE("invalid_code", "That code did not work. Codes expire after 48 hours, so ask for a fresh one."),
    RATE_LIMITED("rate_limited", "Too many tries. Wait an hour and then try again."),
    ALREADY_IN_GROUP(
        "already_in_group",
        "This account already has a care circle with a record in it, and an account can be in one circle at a time. " +
            "Open Sharing and leave your circle to use this code, or ask whoever invited you to join yours instead.",
    );

    companion object {
        fun of(raw: String?) = entries.firstOrNull { it.raw == raw } ?: INVALID_CODE
    }
}

class GroupError(message: String) : Exception(message)

/**
 * Everything the Sharing screens ask the server. Every mutation is a
 * security-definer RPC; `group_members` has no client write policy at all.
 * Fronted by an interface so JVM tests and the debug fake backend can stand in.
 */
interface GroupBackend {
    suspend fun memberships(userId: UUID): List<Membership>
    suspend fun billing(groupId: UUID): Billing?
    suspend fun members(groupId: UUID): List<MemberRow>
    suspend fun grants(groupId: UUID): List<Pair<UUID, UUID>>
    suspend fun pendingInvites(groupId: UUID): List<PendingInvite>
    suspend fun createGroup(name: String): UUID
    suspend fun renameGroup(groupId: UUID, name: String)
    suspend fun generateInvite(groupId: UUID, role: GroupRole, recipientId: UUID?, email: String?, ttlHours: Int): String
    suspend fun revokeInvite(code: String)
    /** (ok, joined group, error code). */
    suspend fun acceptInvite(code: String): Triple<Boolean, UUID?, String?>
    suspend fun setMemberAccess(groupId: UUID, userId: UUID, scope: AccessScope, recipientIds: Set<UUID>)
    suspend fun changeRole(groupId: UUID, userId: UUID, role: GroupRole)
    suspend fun removeMember(groupId: UUID, userId: UUID)
    suspend fun transferOwnership(groupId: UUID, userId: UUID)
    suspend fun leaveGroup(groupId: UUID)
    suspend fun deleteGroup(groupId: UUID)
    suspend fun updateDisplayName(userId: UUID, name: String)
    suspend fun deleteAccount()
}

data class MemberRow(val userId: UUID, val role: GroupRole, val joinedAt: Instant, val accessScope: AccessScope, val displayName: String)

class SupabaseGroupBackend(private val client: SupabaseClient) : GroupBackend {
    override suspend fun memberships(userId: UUID): List<Membership> =
        rows(client.select("group_members?select=role,joined_at,groups(id,name)&user_id=eq.$userId&removed_at=is.null&order=joined_at.asc"))
            .mapNotNull { row ->
                val group = row.optJSONObject("groups") ?: return@mapNotNull null
                Membership(group.uuid("id"), group.optString("name"), GroupRole.of(row.textOrNull("role"), GroupRole.SUBJECT), time(row, "joined_at"))
            }

    override suspend fun billing(groupId: UUID): Billing? =
        rows(client.select("group_billing?select=entitlement,expires_at,is_lifetime&group_id=eq.$groupId&limit=1")).firstOrNull()?.let {
            Billing(it.optString("entitlement", "free"), SyncWire.instant(it.textOrNull("expires_at")), it.optBoolean("is_lifetime"))
        }

    override suspend fun members(groupId: UUID): List<MemberRow> {
        val base = "group_members?group_id=eq.$groupId&removed_at=is.null&order=joined_at.asc&select="
        // `access_scope` exists only once 0018 is applied; PostgREST fails a select naming an unknown column.
        val raw = try {
            client.select(base + "user_id,role,joined_at,access_scope,profiles(display_name)")
        } catch (e: SupabaseError.Http) {
            client.select(base + "user_id,role,joined_at,profiles(display_name)")
        }
        return rows(raw).map {
            MemberRow(
                userId = it.uuid("user_id"),
                role = GroupRole.of(it.textOrNull("role"), GroupRole.CAREGIVER),
                joinedAt = time(it, "joined_at"),
                accessScope = AccessScope.of(it.textOrNull("access_scope")),
                displayName = it.optJSONObject("profiles")?.optString("display_name").orEmpty(),
            )
        }
    }

    override suspend fun grants(groupId: UUID): List<Pair<UUID, UUID>> =
        rows(client.select("recipient_access?select=user_id,care_recipient_id&group_id=eq.$groupId")).map {
            it.uuid("user_id") to it.uuid("care_recipient_id")
        }

    override suspend fun pendingInvites(groupId: UUID): List<PendingInvite> =
        rows(client.select("invite_codes?select=code,intended_email,role_to_grant,care_recipient_id,expires_at&group_id=eq.$groupId&used_at=is.null&revoked_at=is.null&order=created_at.desc"))
            .map {
                PendingInvite(
                    code = it.getString("code"),
                    email = it.textOrNull("intended_email"),
                    role = GroupRole.of(it.textOrNull("role_to_grant"), GroupRole.CAREGIVER),
                    recipientId = it.uuidOrNull("care_recipient_id"),
                    expiresAt = time(it, "expires_at"),
                )
            }

    override suspend fun createGroup(name: String): UUID =
        UUID.fromString(unquote(client.rpc("create_group", JSONObject().put("p_name", name))))

    override suspend fun renameGroup(groupId: UUID, name: String) =
        client.patch("groups?id=eq.$groupId", JSONObject().put("name", name))

    // Every RPC parameter is text and cast inside, so PostgREST never has to choose an overload (D11).
    override suspend fun generateInvite(groupId: UUID, role: GroupRole, recipientId: UUID?, email: String?, ttlHours: Int): String {
        val args = JSONObject().put("p_group_id", groupId.toString()).put("p_role", role.raw).put("p_ttl_hours", ttlHours)
        recipientId?.let { args.put("p_care_recipient_id", it.toString()) }
        email?.let { args.put("p_email", it) }
        return unquote(client.rpc("generate_invite_code", args))
    }

    override suspend fun revokeInvite(code: String) {
        client.rpc("revoke_invite_code", JSONObject().put("p_code", code))
    }

    override suspend fun acceptInvite(code: String): Triple<Boolean, UUID?, String?> {
        val row = rows(client.rpc("accept_invite", JSONObject().put("p_code", code))).firstOrNull()
            ?: return Triple(false, null, InviteFailure.INVALID_CODE.raw)
        return Triple(row.optBoolean("ok"), row.uuidOrNull("joined_group_id"), row.textOrNull("error_code"))
    }

    override suspend fun setMemberAccess(groupId: UUID, userId: UUID, scope: AccessScope, recipientIds: Set<UUID>) {
        val args = JSONObject().put("p_group_id", groupId.toString()).put("p_user_id", userId.toString()).put("p_scope", scope.raw)
        args.put("p_recipient_ids", if (scope == AccessScope.LISTED) JSONArray(recipientIds.map(UUID::toString)) else JSONObject.NULL)
        client.rpc("set_member_access", args)
    }

    override suspend fun changeRole(groupId: UUID, userId: UUID, role: GroupRole) {
        client.rpc("change_role", JSONObject().put("p_group_id", groupId.toString()).put("p_user_id", userId.toString()).put("p_role", role.raw))
    }

    override suspend fun removeMember(groupId: UUID, userId: UUID) {
        client.rpc("remove_member", JSONObject().put("p_group_id", groupId.toString()).put("p_user_id", userId.toString()))
    }

    override suspend fun transferOwnership(groupId: UUID, userId: UUID) {
        client.rpc("transfer_ownership", JSONObject().put("p_group_id", groupId.toString()).put("p_new_owner_id", userId.toString()))
    }

    override suspend fun leaveGroup(groupId: UUID) {
        client.rpc("leave_group", JSONObject().put("p_group_id", groupId.toString()))
    }

    override suspend fun deleteGroup(groupId: UUID) {
        client.rpc("delete_group", JSONObject().put("p_group_id", groupId.toString()))
    }

    override suspend fun updateDisplayName(userId: UUID, name: String) =
        client.patch("profiles?id=eq.$userId", JSONObject().put("display_name", name))

    override suspend fun deleteAccount() {
        client.rpc("delete_account")
    }

    private fun rows(raw: String): List<JSONObject> {
        val array = JSONArray(raw)
        return (0 until array.length()).map { array.getJSONObject(it) }
    }

    private fun time(o: JSONObject, key: String): Instant = SyncWire.instant(o.textOrNull(key)) ?: Instant.EPOCH

    /** A scalar RPC result arrives as a JSON string literal. */
    private fun unquote(raw: String): String {
        val trimmed = raw.trim()
        if (!trimmed.startsWith("\"")) throw IOException("Unexpected reply from the server.")
        return JSONArray("[$trimmed]").getString(0)
    }
}
