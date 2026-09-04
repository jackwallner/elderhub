import SwiftUI

/// The one phone field in the app. Both places that take a number (emergency
/// contacts and providers) use it, so the keyboard, the content type and the
/// grouping cannot drift apart between them.
struct PhoneNumberField: View {
    let title: String
    @Binding var text: String

    @FocusState private var isFocused: Bool

    init(_ title: String = "Phone", text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        TextField(title, text: $text)
            .textContentType(.telephoneNumber)
            .keyboardType(.phonePad)
            .focused($isFocused)
            .onChange(of: text) { old, new in
                // Rewriting the binding puts the caret back at the end of the
                // field, which is where it already was while somebody is
                // typing a number in. It is not where it was when they tapped
                // into the middle of one to correct a digit: reformatting
                // there threw them to the end of the number, so the next
                // backspace took the wrong digit and correcting a phone number
                // on the emergency card turned into retyping it. Format the
                // tail edits, leave a mid-string edit exactly as typed, and
                // tidy the result when the field is done with.
                guard PhoneNumberFormat.isTailEdit(from: old, to: new) else { return }
                let formatted = PhoneNumberFormat.formatted(new)
                if formatted != new { text = formatted }
            }
            .onChange(of: isFocused) { _, focused in
                guard !focused else { return }
                let formatted = PhoneNumberFormat.formatted(text)
                if formatted != text { text = formatted }
            }
            .onAppear {
                // Tidies a number typed before this existed, on the next edit.
                text = PhoneNumberFormat.formatted(text)
            }
    }
}
