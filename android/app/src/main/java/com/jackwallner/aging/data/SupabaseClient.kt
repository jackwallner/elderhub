package com.jackwallner.aging.data

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * Publishable, client-safe values, identical to the iOS Info.plist. Row level
 * security is the boundary; the service-role key never appears in app code.
 */
object SupabaseConfig {
    const val URL = "https://oygrxltpydcmmdtbreec.supabase.co"
    const val PUBLISHABLE_KEY = "sb_publishable_wR8T_YNHdAsPazCfQ6cicg_2WwNlI-Q"
    const val REST = "$URL/rest/v1"
    const val AUTH = "$URL/auth/v1"
}

/** What reached the server and what it said. A transport failure throws [IOException] instead. */
data class HttpResponse(val code: Int, val body: String)

/** One HTTP exchange. The app sends real requests; JVM tests answer from a script. */
fun interface HttpTransport {
    suspend fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse
}

object UrlConnectionTransport : HttpTransport {
    override suspend fun send(method: String, url: String, headers: Map<String, String>, body: String?): HttpResponse =
        withContext(Dispatchers.IO) {
            val conn = URL(url).openConnection() as HttpURLConnection
            try {
                conn.requestMethod = method
                conn.connectTimeout = 15_000
                conn.readTimeout = 30_000
                headers.forEach(conn::setRequestProperty)
                if (body != null) {
                    conn.doOutput = true
                    conn.outputStream.use { it.write(body.toByteArray()) }
                }
                val code = conn.responseCode
                val stream = if (code in 200..299) conn.inputStream else conn.errorStream
                HttpResponse(code, stream?.bufferedReader()?.use { it.readText() } ?: "")
            } finally {
                conn.disconnect()
            }
        }
}

/** Why a request failed, phrased the way the sync and auth rules need it. */
sealed class SupabaseError(message: String) : IOException(message) {
    /** The server answered and refused. [code] is the PostgREST or GoTrue error code when there is one. */
    class Http(val status: Int, val code: String, val serverMessage: String) :
        SupabaseError(serverMessage.ifEmpty { "The server refused the request ($status)." })

    object NotSignedIn : SupabaseError("Sign in first.")

    /** The refresh token was definitively rejected: the account is genuinely signed out. */
    object SessionRevoked : SupabaseError("Your session ended. Sign in again.")

    companion object {
        fun from(response: HttpResponse): Http {
            val json = runCatching { JSONObject(response.body) }.getOrNull()
            // GoTrue sends `error_code` beside a numeric `code`; PostgREST sends a string `code` like "42501".
            val code = json?.optString("error_code").orEmpty()
                .ifEmpty { json?.opt("code") as? String ?: "" }
                .ifEmpty { json?.optString("error").orEmpty() }
            val message = json?.optString("message").orEmpty().ifEmpty { json?.optString("msg").orEmpty() }
                .ifEmpty { json?.optString("error_description").orEmpty() }
            return Http(response.code, code, message)
        }
    }
}

/** Session ownership, fronted by an interface so the debug fake backend can sign in without Google. */
interface AuthBackend {
    val session: Session?
    suspend fun signInWithIdToken(provider: String, idToken: String, rawNonce: String?): Session
    suspend fun refresh(): Session
    suspend fun signOut()
    fun forgetSession()
    fun rememberDisplayName(name: String)
}

data class Session(
    val accessToken: String,
    val refreshToken: String,
    val expiresAtMillis: Long,
    val userId: String,
    val displayName: String,
)

/** Where the session is kept between launches. SharedPreferences on the phone. */
interface SessionStore {
    fun load(): Session?
    fun save(session: Session)
    fun clear()
}

class KeyValueSessionStore(private val values: KeyValueStore) : SessionStore {
    override fun load(): Session? {
        val access = values.getString("supabase.access") ?: return null
        return Session(
            accessToken = access,
            refreshToken = values.getString("supabase.refresh").orEmpty(),
            expiresAtMillis = values.getLong("supabase.expires"),
            userId = values.getString("supabase.user").orEmpty(),
            displayName = values.getString("supabase.name").orEmpty(),
        )
    }

    override fun save(session: Session) {
        values.putString("supabase.access", session.accessToken)
        values.putString("supabase.refresh", session.refreshToken)
        values.putLong("supabase.expires", session.expiresAtMillis)
        values.putString("supabase.user", session.userId)
        values.putString("supabase.name", session.displayName)
    }

    override fun clear() {
        listOf("supabase.access", "supabase.refresh", "supabase.expires", "supabase.user", "supabase.name").forEach(values::remove)
    }
}

/**
 * Minimal Supabase client over [HttpTransport], the Android twin of the iOS
 * SDK use: id_token exchange, session persistence and refresh, and
 * authenticated REST and RPC calls. Same project, same RLS as iOS.
 *
 * The session is read from storage with no network, so a cached care record
 * opens signed in with no signal. Only a definitive rejection of the refresh
 * token signs anybody out ([isRevocation]); a transport failure never does.
 */
class SupabaseClient(
    private val sessions: SessionStore,
    private val transport: HttpTransport = UrlConnectionTransport,
    private val clock: () -> Long = System::currentTimeMillis,
) : AuthBackend {
    private val lock = Mutex()
    @Volatile override var session: Session? = sessions.load()
        private set

    override fun forgetSession() {
        session = null
        sessions.clear()
    }

    /** Exchange a provider id_token (Google on Android, Apple on iOS) for a Supabase session. */
    override suspend fun signInWithIdToken(provider: String, idToken: String, rawNonce: String?): Session {
        val body = JSONObject().put("provider", provider).put("id_token", idToken)
        if (rawNonce != null) body.put("nonce", rawNonce)
        return storeSession(send("POST", "${SupabaseConfig.AUTH}/token?grant_type=id_token", body.toString(), bearer = null))
    }

    /** Refreshes now. Throws [SupabaseError.SessionRevoked] only on a definitive rejection. */
    override suspend fun refresh(): Session = lock.withLock { refreshLocked() }

    private suspend fun refreshLocked(): Session {
        val current = session ?: throw SupabaseError.NotSignedIn
        val body = JSONObject().put("refresh_token", current.refreshToken).toString()
        return try {
            storeSession(send("POST", "${SupabaseConfig.AUTH}/token?grant_type=refresh_token", body, bearer = null), current.displayName)
        } catch (e: SupabaseError.Http) {
            if (!isRevocation(e)) throw e
            forgetSession()
            throw SupabaseError.SessionRevoked
        }
    }

    suspend fun accessToken(): String = lock.withLock {
        val current = session ?: throw SupabaseError.NotSignedIn
        if (current.expiresAtMillis - clock() > 120_000) return@withLock current.accessToken
        refreshLocked().accessToken
    }

    override suspend fun signOut() {
        val token = session?.accessToken
        if (token != null) runCatching { send("POST", "${SupabaseConfig.AUTH}/logout", "{}", bearer = token) }
        forgetSession()
    }

    override fun rememberDisplayName(name: String) {
        val current = session ?: return
        session = current.copy(displayName = name).also(sessions::save)
    }

    /** GET rows with a raw PostgREST query, e.g. `medications?select=*&group_id=eq.<id>`. */
    suspend fun select(pathAndQuery: String): String = send("GET", "${SupabaseConfig.REST}/$pathAndQuery", null, accessToken())

    suspend fun rpc(fn: String, args: JSONObject = JSONObject()): String =
        send("POST", "${SupabaseConfig.REST}/rpc/$fn", args.toString(), accessToken())

    suspend fun upsert(table: String, onConflict: String, row: JSONObject) {
        send(
            "POST", "${SupabaseConfig.REST}/$table?on_conflict=$onConflict", "[$row]", accessToken(),
            prefer = "resolution=merge-duplicates,return=minimal",
        )
    }

    suspend fun patch(pathAndQuery: String, body: JSONObject) {
        send("PATCH", "${SupabaseConfig.REST}/$pathAndQuery", body.toString(), accessToken(), prefer = "return=minimal")
    }

    private fun storeSession(raw: String, fallbackName: String = ""): Session {
        val o = JSONObject(raw)
        val user = o.getJSONObject("user")
        val meta = user.optJSONObject("user_metadata")
        val name = listOf("display_name", "full_name", "name")
            .map { meta?.optString(it).orEmpty().trim() }
            .firstOrNull { it.isNotEmpty() } ?: fallbackName
        val s = Session(
            accessToken = o.getString("access_token"),
            refreshToken = o.getString("refresh_token"),
            expiresAtMillis = clock() + o.optLong("expires_in", 3600) * 1000,
            userId = user.getString("id"),
            displayName = name,
        )
        session = s
        sessions.save(s)
        return s
    }

    private suspend fun send(method: String, url: String, body: String?, bearer: String?, prefer: String? = null): String {
        val headers = buildMap {
            put("apikey", SupabaseConfig.PUBLISHABLE_KEY)
            put("Authorization", "Bearer ${bearer ?: SupabaseConfig.PUBLISHABLE_KEY}")
            if (body != null) put("Content-Type", "application/json")
            if (prefer != null) put("Prefer", prefer)
        }
        val response = transport.send(method, url, headers, body)
        if (response.code !in 200..299) throw SupabaseError.from(response)
        return response.body
    }

    companion object {
        /**
         * Deliberately narrow, like `AuthService.classify` on iOS: only these
         * GoTrue codes mean the session is really over. Anything else, including
         * a 5xx or an unrecognised 400, keeps the session and the cached record.
         */
        private val REVOKING_CODES = setOf(
            "refresh_token_not_found", "refresh_token_already_used", "session_not_found",
            "session_expired", "user_not_found", "user_banned", "bad_jwt",
        )

        fun isRevocation(error: SupabaseError.Http): Boolean = error.code in REVOKING_CODES
    }
}
