import Foundation
import Testing

@testable import Aging

struct PhoneNumberFormatTests {

    // MARK: Grouping

    @Test func tenDigitsGroupAsAreaCodePrefixLine() {
        #expect(PhoneNumberFormat.formatted("5551234567") == "555-123-4567")
    }

    @Test func elevenDigitsStartingWithOneKeepTheCountryCode() {
        #expect(PhoneNumberFormat.formatted("15551234567") == "1-555-123-4567")
    }

    @Test func commonHandTypedShapesAreNormalised() {
        #expect(PhoneNumberFormat.formatted("(555) 123-4567") == "555-123-4567")
        #expect(PhoneNumberFormat.formatted("555.123.4567") == "555-123-4567")
        #expect(PhoneNumberFormat.formatted("1 (555) 123 4567") == "1-555-123-4567")
    }

    @Test func formattingIsIdempotent() {
        let once = PhoneNumberFormat.formatted("5551234567")
        #expect(PhoneNumberFormat.formatted(once) == once)
    }

    // MARK: Typing and deleting

    @Test func partialEntryNeverEndsOnASeparator() {
        // A trailing dash put back by the formatter is a field backspace
        // cannot get out of.
        #expect(PhoneNumberFormat.formatted("555") == "555")
        #expect(PhoneNumberFormat.formatted("5551") == "555-1")
        #expect(PhoneNumberFormat.formatted("555123") == "555-123")
        #expect(PhoneNumberFormat.formatted("5551234") == "555-123-4")
    }

    @Test func deletingADigitShortensTheGroupingRatherThanRestoringIt() {
        #expect(PhoneNumberFormat.formatted("555-123") == "555-123")
        #expect(PhoneNumberFormat.formatted("555-12") == "555-12")
        #expect(PhoneNumberFormat.formatted("55") == "55")
    }

    @Test func emptyStaysEmpty() {
        #expect(PhoneNumberFormat.formatted("") == "")
    }

    // MARK: Anything we do not understand is left alone

    @Test func internationalNumbersArePassedThrough() {
        #expect(PhoneNumberFormat.formatted("+44 20 7946 0018") == "+44 20 7946 0018")
        #expect(PhoneNumberFormat.formatted("+1 555 123 4567") == "+1 555 123 4567")
    }

    @Test func extensionsAndLettersArePassedThrough() {
        #expect(PhoneNumberFormat.formatted("555-123-4567 x24") == "555-123-4567 x24")
        #expect(PhoneNumberFormat.formatted("1-800-FLOWERS") == "1-800-FLOWERS")
    }

    @Test func numbersTooLongToGroupArePassedThrough() {
        #expect(PhoneNumberFormat.formatted("442079460018") == "442079460018")
        #expect(PhoneNumberFormat.formatted("25551234567") == "25551234567")
    }

    @Test func shortCodesAreLeftAsShortCodes() {
        #expect(PhoneNumberFormat.formatted("911") == "911")
        #expect(PhoneNumberFormat.formatted("988") == "988")
    }
}
