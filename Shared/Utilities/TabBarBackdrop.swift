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

    /// A solid strip behind the navigation bar, over the scrolled content, so
    /// a row that has scrolled up under the bar is hidden rather than blurred
    /// behind the title (a card's words showed through the glass at the top
    /// of Today). The bar itself, large title included, still draws above it.
    /// The unfolded Duo's panes keep the system bar, whose placement beside
    /// the status band is tuned (see `.claude/rules/iphone-duo.md`).
    func navigationBarBackdrop() -> some View {
        modifier(NavigationBarBackdrop())
    }
}

private struct NavigationBarBackdrop: ViewModifier {
    @Environment(\.isUnfoldedPane) private var isUnfoldedPane

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if !isUnfoldedPane {
                GeometryReader { proxy in
                    Color(uiColor: .systemGroupedBackground)
                        .frame(height: proxy.safeAreaInsets.top)
                        .offset(y: -proxy.safeAreaInsets.top)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
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
