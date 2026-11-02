import SwiftUI

extension View {
    /// A solid strip behind the system tab bar, drawn under the bar and over
    /// the tab's content. The floating glass bar lets whatever rests under it
    /// show through (a card's words ran through the tab labels at large text
    /// sizes), so a screen that reaches the bottom edge gets a backdrop in its
    /// own background colour and its content stops where the bar starts.
    func tabBarBackdrop(_ isShown: Bool = true) -> some View {
        overlay(alignment: .bottom) {
            if isShown {
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

    /// The navigation bar in the screen's own background colour, so a row
    /// scrolled up under it is hidden rather than blurred behind the title
    /// (a card's words showed through the glass at the top of Today). The
    /// unfolded Duo's panes keep the system bar, whose placement beside the
    /// status band is tuned (see `.claude/rules/iphone-duo.md`).
    func opaqueNavigationBar() -> some View {
        modifier(OpaqueNavigationBar())
    }
}

private struct OpaqueNavigationBar: ViewModifier {
    @Environment(\.isUnfoldedPane) private var isUnfoldedPane

    @ViewBuilder
    func body(content: Content) -> some View {
        if isUnfoldedPane {
            content
        } else if #available(iOS 18, *) {
            content
                .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        } else {
            content
                .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
