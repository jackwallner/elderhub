package com.jackwallner.aging.model

/** Port of the emergency card's `telURL`: drop any extension, keep digits and plus signs. */
object Phone {
    fun dialable(phone: String): String? {
        val beforeExtension = phone.lowercase().split('x', '#', ',', ';').first()
        val digits = beforeExtension.filter { it.isDigit() || it == '+' }
        return digits.ifEmpty { null }
    }
}
