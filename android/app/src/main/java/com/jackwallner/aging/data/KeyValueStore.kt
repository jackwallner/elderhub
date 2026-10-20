package com.jackwallner.aging.data

import android.content.Context
import android.content.SharedPreferences

/**
 * The UserDefaults of this port. Every store takes one, so unit tests run on
 * the JVM against `InMemoryStore` and the app runs on SharedPreferences with
 * the same keys iOS uses.
 */
interface KeyValueStore {
    fun contains(key: String): Boolean
    fun getInt(key: String, default: Int = 0): Int
    fun getLong(key: String, default: Long = 0): Long
    fun getBoolean(key: String, default: Boolean = false): Boolean
    fun getString(key: String): String?
    fun getStringSet(key: String): Set<String>
    fun keys(): Set<String>
    fun putInt(key: String, value: Int)
    fun putLong(key: String, value: Long)
    fun putBoolean(key: String, value: Boolean)
    fun putString(key: String, value: String)
    fun putStringSet(key: String, value: Set<String>)
    fun remove(key: String)
}

class SharedPreferencesStore(private val prefs: SharedPreferences) : KeyValueStore {
    constructor(context: Context) : this(context.getSharedPreferences("aging", Context.MODE_PRIVATE))

    override fun contains(key: String) = prefs.contains(key)
    override fun getInt(key: String, default: Int) = prefs.getInt(key, default)
    override fun getLong(key: String, default: Long) = prefs.getLong(key, default)
    override fun getBoolean(key: String, default: Boolean) = prefs.getBoolean(key, default)
    override fun getString(key: String): String? = prefs.getString(key, null)
    override fun getStringSet(key: String): Set<String> = prefs.getStringSet(key, null)?.toSet() ?: emptySet()
    override fun keys(): Set<String> = prefs.all.keys
    override fun putInt(key: String, value: Int) = prefs.edit().putInt(key, value).apply()
    override fun putLong(key: String, value: Long) = prefs.edit().putLong(key, value).apply()
    override fun putBoolean(key: String, value: Boolean) = prefs.edit().putBoolean(key, value).apply()
    override fun putString(key: String, value: String) = prefs.edit().putString(key, value).apply()
    override fun putStringSet(key: String, value: Set<String>) = prefs.edit().putStringSet(key, value).apply()
    override fun remove(key: String) = prefs.edit().remove(key).apply()
}

class InMemoryStore : KeyValueStore {
    private val values = mutableMapOf<String, Any>()

    override fun contains(key: String) = key in values
    override fun getInt(key: String, default: Int) = values[key] as? Int ?: default
    override fun getLong(key: String, default: Long) = values[key] as? Long ?: default
    override fun getBoolean(key: String, default: Boolean) = values[key] as? Boolean ?: default
    override fun getString(key: String) = values[key] as? String

    @Suppress("UNCHECKED_CAST")
    override fun getStringSet(key: String) = values[key] as? Set<String> ?: emptySet()
    override fun keys(): Set<String> = values.keys.toSet()
    override fun putInt(key: String, value: Int) { values[key] = value }
    override fun putLong(key: String, value: Long) { values[key] = value }
    override fun putBoolean(key: String, value: Boolean) { values[key] = value }
    override fun putString(key: String, value: String) { values[key] = value }
    override fun putStringSet(key: String, value: Set<String>) { values[key] = value.toSet() }
    override fun remove(key: String) { values.remove(key) }
}

const val DAY_MS = 86_400_000L
