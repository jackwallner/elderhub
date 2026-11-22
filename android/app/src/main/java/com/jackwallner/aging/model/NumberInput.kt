package com.jackwallner.aging.model

import java.text.DecimalFormatSymbols
import java.util.Locale

/** Reads a typed number the way the phone's keypad writes it (iOS `VitalReading.value(from:locale:)`). */
object NumberInput {
    private val plain = Regex("""[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?""")

    /**
     * `toDoubleOrNull` only understands a dot, and where the region writes decimals with a comma
     * the number pad types one, so "12,5" was not a number. A dot is accepted in every region,
     * because that is how an existing value is loaded back into the field. A separator that means
     * something else where the phone is (the comma that groups thousands in en_US) is refused
     * rather than guessed at, and so is anything that is not a finite number.
     */
    fun value(text: String, locale: Locale = Locale.getDefault()): Double? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null
        finite(trimmed)?.let { return it }
        val separator = DecimalFormatSymbols.getInstance(locale).decimalSeparator
        if (separator == '.' || trimmed.count { it == separator } != 1) return null
        return finite(trimmed.replace(separator, '.'))
    }

    private fun finite(text: String): Double? =
        if (plain.matches(text)) text.toDoubleOrNull()?.takeIf { it.isFinite() } else null
}
