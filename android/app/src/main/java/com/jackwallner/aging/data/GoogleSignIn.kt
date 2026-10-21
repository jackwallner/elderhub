package com.jackwallner.aging.data

import android.app.Activity
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.jackwallner.aging.BuildConfig
import java.security.MessageDigest
import java.security.SecureRandom

/** What a provider hands back: the id_token, the raw nonce whose hash it carries, and the name it already knows. */
data class ProviderCredential(val provider: String, val idToken: String, val rawNonce: String?, val displayName: String)

/** Where a sign-in credential comes from. Google on a real phone; a canned one in the debug fake backend. */
interface IdTokenSource {
    val isAvailable: Boolean

    /** Throws [SignInCancelled] when the person backs out, which is not an error worth showing. */
    suspend fun request(activity: Activity): ProviderCredential
}

class SignInCancelled : Exception()

/**
 * Sign in with Google, the Android counterpart of Sign in with Apple:
 * Credential Manager returns a Google id_token carrying the SHA-256 of a raw
 * nonce, and Supabase verifies both (`grant_type=id_token`, provider google).
 * Needs the Web OAuth client id the Supabase Google provider trusts; without
 * one [isAvailable] is false and the button is not shown at all.
 */
object GoogleSignIn : IdTokenSource {
    override val isAvailable: Boolean get() = BuildConfig.GOOGLE_WEB_CLIENT_ID.isNotBlank()

    override suspend fun request(activity: Activity): ProviderCredential {
        val rawNonce = randomNonce()
        val option = GetSignInWithGoogleOption.Builder(BuildConfig.GOOGLE_WEB_CLIENT_ID)
            .setNonce(sha256(rawNonce))
            .build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        val result = try {
            CredentialManager.create(activity).getCredential(activity, request)
        } catch (_: GetCredentialCancellationException) {
            throw SignInCancelled()
        } catch (_: NoCredentialException) {
            throw IllegalStateException("Add a Google account to this phone in Settings, then try again.")
        }
        val credential = result.credential
        if (credential !is CustomCredential || credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
            error("Google did not return a sign-in token. Please try again.")
        }
        val google = GoogleIdTokenCredential.createFrom(credential.data)
        return ProviderCredential("google", google.idToken, rawNonce, google.displayName.orEmpty().trim())
    }

    fun randomNonce(length: Int = 32): String {
        val chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._"
        val rng = SecureRandom()
        return String(CharArray(length) { chars[rng.nextInt(chars.length)] })
    }

    fun sha256(input: String): String =
        MessageDigest.getInstance("SHA-256").digest(input.toByteArray()).joinToString("") { "%02x".format(it) }
}
