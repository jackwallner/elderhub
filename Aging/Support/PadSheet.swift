import SwiftUI

extension View {
    /// A sheet that does not inherit the root TabView's iPad column margin. That
    /// margin is sized for the full screen, so on a narrow form sheet it can
    /// leave a form with no width at all (the medication editor, iPad landscape).
    func padSheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content().contentMargins(.horizontal, 0, for: .scrollContent)
        }
    }

    func padSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { value in
            content(value).contentMargins(.horizontal, 0, for: .scrollContent)
        }
    }
}
