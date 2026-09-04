import Foundation

/// As-you-type formatting for the phone fields (emergency contacts and
/// providers).
///
/// A number that reaches the emergency card is read aloud off a screen by
/// somebody under stress, so `5551234567` is the wrong thing to print. This
/// groups it the way North American numbers are written: `555-123-4567`, and
/// `1-555-123-4567` once a country code is actually typed.
///
/// Two rules keep it from getting in the way of typing:
///
/// - It never appends a trailing separator. If a digit is deleted so the value
///   ends where a dash would go, formatting the shorter string must not put
///   that dash straight back, or backspace stops working on the field.
/// - Anything it does not recognise is returned untouched: a leading `+`, an
///   extension ("555-0101 x24"), a short code, a number with letters in it.
///   Guessing at the grouping of an international number would only mangle it,
///   and the field is free text in the model either way.
///
/// `formatted` is idempotent, so it is safe to run on every keystroke and on
/// the value loaded from an existing row.
enum PhoneNumberFormat {

    /// Characters a formatted or hand-typed North American number may contain.
    /// Anything else means we are looking at something we do not understand.
    private static let punctuation = Set(" -().")

    static func formatted(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return input }
        guard trimmed.allSatisfy({ $0.isNumber || punctuation.contains($0) }) else { return input }

        let digits = trimmed.filter(\.isNumber)
        switch digits.count {
        case 1...10:
            return grouped(digits)
        case 11 where digits.first == "1":
            return "1-" + grouped(String(digits.dropFirst()))
        default:
            return input
        }
    }

    /// Whether an edit that took `old` to `new` happened at the end of the
    /// field: a character appended, or one deleted off the end.
    ///
    /// The field re-formats on a tail edit only. Writing the binding back puts
    /// the caret at the end of the text, which is where it already is while a
    /// number is being typed in, and is not where it is when somebody has
    /// tapped into the middle of one to correct a digit. Re-formatting there
    /// moved them to the end, so the next backspace took the wrong digit.
    static func isTailEdit(from old: String, to new: String) -> Bool {
        new.hasPrefix(old) || old.hasPrefix(new)
    }

    /// Groups up to ten digits as `xxx-xxx-xxxx`, adding a separator only
    /// ahead of a digit that exists.
    private static func grouped(_ digits: String) -> String {
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index == 3 || index == 6 { out.append("-") }
            out.append(digit)
        }
        return out
    }
}
