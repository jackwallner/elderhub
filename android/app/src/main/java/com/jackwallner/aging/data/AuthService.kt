package com.jackwallner.aging.data

import android.app.Activity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.UUID

/** The server side of the app, swappable as one piece so the debug fake backend replaces all of it at once. */
class Cloud(
    val auth: AuthBackend,
    val groups: GroupBackend,
    val sync: SyncRemote,
    val idTokens: IdTokenSource,
    /** True only for the debug in-memory backend. Never in a release or QA build. */
    val isFake: Boolean = false,
) {
    companion object {
        fun supabase(values: KeyValueStore): Cloud {
            val client = SupabaseClient(KeyValueSessionStore(values))
            return Cloud(client, SupabaseGroupBackend(client), SupabaseSyncRemote(client), GoogleSignIn)
        }
    }
}

sealed interface AuthState {
    /** Before the first bootstrap. Never rendered as signed out. */
    object Unknown : AuthState
    object SignedOut : AuthState
    data class SignedIn(val userId: UUID) : AuthState
}

/**
 * Session ownership, port of `AuthService.swift`, built around the same
 * requirement: someone in an emergency room with no signal lands in the app
 * holding the medication list, not on a sign-in screen.
 *
 * [bootstrap] reads the stored session with no network. [refreshInBackground]
 * runs after the UI is up, and only a definitive rejection of the refresh token
 * signs anyone out; a transport failure only sets [isOffline].
 *
 * Accounts: Android signs in with Google, iOS with Apple. One person who uses
 * both is two Supabase users, two `profiles` rows and, inside one circle, two
 * members. Nothing here links or merges them: there is no automatic match on
 * email, because the Apple address is often a private relay and a silent merge
 * would hand one account's circle to another.
 */
class AuthService(private val cloud: () -> Cloud) {
    var state by mutableStateOf<AuthState>(AuthState.Unknown)
        private set
    var isOffline by mutableStateOf(false)
        private set
    var displayName by mutableStateOf("")
        private set

    val userId: UUID? get() = (state as? AuthState.SignedIn)?.userId
    val isSignedIn: Boolean get() = userId != null

    /** Whether this build can offer sign-in at all. Hidden, not disabled, when it cannot. */
    val canSignIn: Boolean get() = cloud().idTokens.isAvailable

    fun bootstrap() {
        val session = cloud().auth.session
        if (session == null) {
            state = AuthState.SignedOut
            displayName = ""
            return
        }
        state = AuthState.SignedIn(UUID.fromString(session.userId))
        displayName = session.displayName
    }

    suspend fun refreshInBackground() {
        val auth = cloud().auth
        if (auth.session == null) return
        try {
            val session = auth.refresh()
            state = AuthState.SignedIn(UUID.fromString(session.userId))
            displayName = session.displayName
            isOffline = false
        } catch (e: SupabaseError.SessionRevoked) {
            forget()
        } catch (e: Exception) {
            // Transport, DNS, a 5xx, an unrecognised refusal: keep the session and the cached record.
            isOffline = true
        }
    }

    /**
     * Google first and only. Whatever the provider already gave (the name) is
     * used and never asked for again on a following screen.
     */
    suspend fun signIn(activity: Activity, groups: GroupBackend = cloud().groups): Session {
        val credential = cloud().idTokens.request(activity)
        val session = cloud().auth.signInWithIdToken(credential.provider, credential.idToken, credential.rawNonce)
        val userId = UUID.fromString(session.userId)
        state = AuthState.SignedIn(userId)
        isOffline = false
        displayName = session.displayName
        if (session.displayName.isEmpty() && credential.displayName.isNotEmpty()) {
            // Non-fatal: the session exists, and a failed profile write must not report a failed sign-in.
            runCatching { groups.updateDisplayName(userId, credential.displayName) }
            cloud().auth.rememberDisplayName(credential.displayName)
            displayName = credential.displayName
        }
        return session
    }

    suspend fun updateDisplayName(name: String) {
        val trimmed = name.trim()
        val id = userId ?: return
        if (trimmed.isEmpty()) return
        cloud().groups.updateDisplayName(id, trimmed)
        cloud().auth.rememberDisplayName(trimmed)
        displayName = trimmed
    }

    suspend fun signOut() {
        runCatching { cloud().auth.signOut() }
        forget()
    }

    /**
     * Play's account-deletion requirement. The RPC hands off or closes any
     * circle this account owns and unlinks it from any record, but never
     * deletes the family's history: rows keep the author's name snapshot.
     */
    suspend fun deleteAccount() {
        cloud().groups.deleteAccount()
        cloud().auth.forgetSession()
        forget()
    }

    private fun forget() {
        cloud().auth.forgetSession()
        state = AuthState.SignedOut
        displayName = ""
    }
}
