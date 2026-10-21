package com.jackwallner.aging.data

import android.net.Uri
import java.net.URLEncoder

/**
 * The shape of an invitation, port of `InviteLink.swift`: what a code looks
 * like, which links carry one, and how a link is read back.
 *
 * Every message carries the https address, because the person most likely to
 * be invited has not installed anything yet. On Android that address is also
 * an App Link (`autoVerify` in the manifest), and `elderhub://invite` is the
 * fallback the join page's button opens.
 */
object InviteLink {
    /** Eight characters from an alphabet without look-alikes (`random_invite_code`, 0004). */
    const val CODE_LENGTH = 8

    /** Mirrored from the repo's `/docs`. Ends up in mail that outlives this build: never change it. */
    const val WEB_BASE = "https://jackwallner.com/ios/elderhub/join.html"
    const val DOWNLOAD_PAGE = "https://jackwallner.com/ios/elderhub/"

    /** Upper-cases and drops anything that is not a letter or digit, so a dictated "H, 7, K" still lands. */
    fun normalized(raw: String): String? {
        val cleaned = raw.uppercase().filter { it.isLetterOrDigit() }
        return cleaned.takeIf { it.length == CODE_LENGTH }
    }

    fun webUrl(code: String) = "$WEB_BASE?code=$code"

    fun appUrl(code: String) = "elderhub://invite?code=$code"

    /** Reads a code out of either address, the same rule as iOS so the two cannot disagree. */
    fun code(scheme: String?, host: String?, path: String?, codeParam: String?): String? {
        val carriesCode = when (scheme?.lowercase()) {
            "elderhub" -> host?.lowercase() == "invite"
            "https", "http" -> path.orEmpty().endsWith("/join.html")
            else -> false
        }
        if (!carriesCode) return null
        return codeParam?.let(::normalized)
    }

    fun code(uri: Uri): String? = code(uri.scheme, uri.host, uri.path, uri.getQueryParameter("code"))

    /** The server's own check (`invite_email_is_normalized`, 0015), so the client and the server agree. */
    fun isValidEmail(raw: String): Boolean {
        val trimmed = raw.trim().lowercase()
        return trimmed.isNotEmpty() && Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$").matches(trimmed)
    }
}

object InviteMessage {
    /**
     * Platform-neutral on purpose: the iOS text says "on your iPhone", and an
     * Android phone may be inviting an iPhone or the other way round.
     */
    fun text(code: String, role: GroupRole, personName: String?): String {
        val access = if (role == GroupRole.SUBJECT) {
            "This invitation links you to ${personName ?: "your"} care record. You will see only that record."
        } else {
            "As a helper, you will be able to see and update everyone in this care circle."
        }
        return """
            |You are invited to a care circle in Elderhub.
            |
            |$access
            |
            |Your invitation code is $code
            |
            |Open this link on your phone to join:
            |${InviteLink.webUrl(code)}
            |
            |That page shows the code and opens Elderhub for you. If you already have the app, choose "I have an invitation" and type the code in.
            |
            |The invitation works once and expires after 48 hours.
        """.trimMargin()
    }

    /** Escaped by hand: the body holds a URL with its own query string, and the address may hold a `+`. */
    fun emailUri(address: String, code: String, role: GroupRole, personName: String?): String? {
        val trimmed = address.trim().lowercase()
        if (!InviteLink.isValidEmail(trimmed)) return null
        return "mailto:${escape(trimmed)}?subject=${escape("Invitation to join Elderhub")}&body=${escape(text(code, role, personName))}"
    }

    private fun escape(value: String) = URLEncoder.encode(value, "UTF-8").replace("+", "%20")
}
