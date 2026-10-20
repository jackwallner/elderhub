package com.jackwallner.aging.data

import java.security.MessageDigest

/** Reusable access for Play reviewers, separate from purchases and developer overrides. */
class ReviewAccess(private val defaults: KeyValueStore, private val expectedDigest: String) {
    val isGranted: Boolean
        get() = expectedDigest.length == 64 && defaults.getString(KEY) == expectedDigest

    fun activate(code: String): Boolean {
        if (!expectedDigest.matches(Regex("[a-f0-9]{64}"))) return false
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(code.trim().toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        if (!MessageDigest.isEqual(digest.toByteArray(), expectedDigest.toByteArray())) return false
        defaults.putString(KEY, expectedDigest)
        return true
    }

    private companion object {
        const val KEY = "subscription.playReviewAccess"
    }
}
