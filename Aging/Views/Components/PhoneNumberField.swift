import SwiftUI

/// The one phone field in the app. Both places that take a number (emergency
/// contacts and providers) use it, so the keyboard, the content type and the
/// grouping cannot drift apart between them.
struct PhoneNumberField: View {
    let title: String
    @Binding var text: String

    init(_ title: String = "Phone", text: Binding<String>) {
        self.title = title
        self._text = text
    }

    var body: some View {
        TextField(title, text: $text)
            .textContentType(.telephoneNumber)
            .keyboardType(.phonePad)
            .onChange(of: text) { _, new in
                let formatted = PhoneNumberFormat.formatted(new)
                if formatted != new { text = formatted }
            }
            .onAppear {
                // Tidies a number typed before this existed, on the next edit.
                text = PhoneNumberFormat.formatted(text)
            }
    }
}
