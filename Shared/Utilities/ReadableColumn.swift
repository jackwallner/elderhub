#if os(iOS)
import SwiftUI

/// Caps a full-width screen at a comfortable reading column on iPad and
/// centres it. On an iPhone, and in an iPad Split View narrower than the cap,
/// the content is already narrower than the column, so nothing changes.
private struct ReadableColumn: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Apply to the content inside a `ScrollView`, so the scroll bar stays at
    /// the screen edge. 640 pt is the width forms and cards read well at.
    func readableColumn(maxWidth: CGFloat = 640) -> some View {
        modifier(ReadableColumn(maxWidth: maxWidth))
    }
}
#endif
