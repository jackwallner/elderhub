import SwiftUI

extension View {
    /// At accessibility text sizes a solid strip behind the system tab bar,
    /// drawn under the bar and over the tab's content. The floating glass bar
    /// lets whatever rests under it show through, and a card's words ran
    /// through the tab labels at AX3. At ordinary sizes the glass stays: rows
    /// read through it cleanly and a hard cut slices the line on the bar.
    func tabBarBackdrop(_ isShown: Bool = true) -> some View {
        modifier(TabBarBackdrop(isShown: isShown))
    }
}

private struct TabBarBackdrop: ViewModifier {
    let isShown: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if isShown, dynamicTypeSize.isAccessibilitySize {
                GeometryReader { proxy in
                    Color(uiColor: .systemGroupedBackground)
                        .frame(height: proxy.safeAreaInsets.bottom)
                        .offset(y: proxy.size.height)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}
