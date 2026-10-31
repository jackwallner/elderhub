import Foundation
import Testing

@testable import Aging

/// The vitals editor read what was typed with `Double(String)`, which only
/// understands a dot. Where the region writes decimals with a comma (Germany,
/// France, Brazil, Spain, Russia, most of Europe and South America) the
/// decimal pad types a comma, so "98,6" was not a number: Save stayed greyed
/// out with no word on screen about why, and a weight or a temperature with a
/// fraction could not be recorded at all.
struct VitalInputTests {
    private let german = Locale(identifier: "de_DE")
    private let french = Locale(identifier: "fr_FR")
    private let english = Locale(identifier: "en_US")

    @Test func aCommaIsTheDecimalPointWhereThePadTypesOne() {
        #expect(VitalReading.value(from: "98,6", locale: german) == 98.6)
        #expect(VitalReading.value(from: "72,5", locale: french) == 72.5)
    }

    @Test func aDotStillMeansTheDecimalPointInEveryLocale() {
        // The editor loads an existing reading back as "98.6" whatever the
        // locale is, so a dot has to survive a German phone too.
        #expect(VitalReading.value(from: "98.6", locale: german) == 98.6)
        #expect(VitalReading.value(from: "98.6", locale: english) == 98.6)
    }

    @Test func wholeNumbersAndStrayWhitespaceParse() {
        #expect(VitalReading.value(from: "120", locale: german) == 120)
        #expect(VitalReading.value(from: " 120 ", locale: english) == 120)
    }

    @Test func textThatIsNotANumberIsRefused() {
        for text in ["", " ", "abc", "98,6,1", "98..6", "9 8", "nan", "inf"] {
            #expect(VitalReading.value(from: text, locale: german) == nil, "accepted \(text)")
        }
    }

    @Test func aCommaIsNotGuessedAtWhereTheLocaleUsesADot() {
        // In en_US a comma groups thousands. Reading "98,6" as 98.6, or as 986,
        // would be a guess about someone's blood pressure.
        #expect(VitalReading.value(from: "98,6", locale: english) == nil)
    }
}
