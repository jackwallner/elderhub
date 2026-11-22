package com.jackwallner.aging

import com.jackwallner.aging.model.NumberInput
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * iOS 51c81ae (`VitalInputTests`). `toDoubleOrNull` only understands a dot, and where the region
 * writes decimals with a comma the number pad types one, so "12,5" read as nothing and the medication's
 * On hand silently saved as 0 (out of stock) and Per dose as 1.
 */
class NumberInputTest {
    private val german = Locale.GERMANY
    private val french = Locale.FRANCE
    private val english = Locale.US

    @Test fun aCommaIsTheDecimalPointWhereThePadTypesOne() {
        assertEquals(98.6, NumberInput.value("98,6", german)!!, 0.0)
        assertEquals(72.5, NumberInput.value("72,5", french)!!, 0.0)
    }

    @Test fun aDotStillMeansTheDecimalPointInEveryLocale() {
        // The editor loads an existing number back with a dot whatever the locale is.
        assertEquals(98.6, NumberInput.value("98.6", german)!!, 0.0)
        assertEquals(98.6, NumberInput.value("98.6", english)!!, 0.0)
    }

    @Test fun wholeNumbersAndStrayWhitespaceParse() {
        assertEquals(120.0, NumberInput.value("120", german)!!, 0.0)
        assertEquals(120.0, NumberInput.value(" 120 ", english)!!, 0.0)
    }

    @Test fun textThatIsNotANumberIsRefused() {
        for (text in listOf("", " ", "abc", "98,6,1", "98..6", "9 8", "nan", "inf", "NaN", "Infinity", "-Infinity", "1e999")) {
            assertNull("accepted $text", NumberInput.value(text, german))
        }
    }

    @Test fun aCommaIsNotGuessedAtWhereTheLocaleUsesADot() {
        // In en_US a comma groups thousands: reading "12,5" as 12.5 or 125 would be a guess about a supply.
        assertNull(NumberInput.value("12,5", english))
    }
}
