import CoreGraphics
#if os(iOS)
import SwiftUI
#endif

/// Pane frames for the unfolded iPhone Duo: the tabs (Today, Sharing,
/// Settings) on the leading side of the fold, Care on the trailing side, so
/// today's doses sit beside the record they belong to and nothing straddles
/// the crease. `nil` keeps the single-column phone layout: every ordinary
/// iPhone, the folded Duo, and the unfolded Duo held in portrait, where each
/// half would be too narrow.
struct UnfoldedSplit: Equatable, Sendable {
    var primaryWidth: CGFloat
    var secondaryX: CGFloat
    var secondaryWidth: CGFloat

    /// Narrowest pane that still fits the phone layout of Today and the hub.
    static let minimumPaneWidth: CGFloat = 360

    /// - Parameters:
    ///   - width: the container's width.
    ///   - fold: the vertical fold's leading and trailing edge in the same
    ///     coordinate space, or `nil` when the system reports none.
    static func make(width: CGFloat, isRegularWidth: Bool, fold: ClosedRange<CGFloat>?) -> UnfoldedSplit? {
        guard isRegularWidth, width >= minimumPaneWidth * 2 else { return nil }
        if let fold,
           fold.lowerBound >= minimumPaneWidth,
           width - fold.upperBound >= minimumPaneWidth {
            return UnfoldedSplit(
                primaryWidth: fold.lowerBound,
                secondaryX: fold.upperBound,
                secondaryWidth: width - fold.upperBound
            )
        }
        let half = (width / 2).rounded(.down)
        return UnfoldedSplit(primaryWidth: half, secondaryX: half, secondaryWidth: width - half)
    }
}

/// The band of blur under the tab bar in the leading pane. `bottomInset` is
/// the tab's bottom safe-area inset, which on the Duo's inner display is the
/// floating bar plus the margin below it, so the bar's top edge sits exactly
/// `bottomInset` above the display's bottom.
struct TabBarEdgeBlur: Equatable, Sendable {
    /// How far above the bar the blur begins. Small, so the row sitting on the
    /// bar keeps its last line crisp instead of fading out (review, 2026-10-23).
    static let leadIn: CGFloat = 6
    /// How far into the bar it reaches full strength, so the start is a soft
    /// ramp rather than a line across the pane.
    static let settle: CGFloat = 10

    var bottomInset: CGFloat

    /// From the first blurred row to the display's bottom edge.
    var height: CGFloat { max(bottomInset, 0) + Self.leadIn }

    /// Where, from the band's top (0) to the display edge (1), the blur
    /// reaches full strength.
    var fullStrengthAt: CGFloat { min((Self.leadIn + Self.settle) / height, 1) }
}

/// What the split is computed from, measured once per layout pass.
struct PaneGeometry: Equatable, Sendable {
    var width: CGFloat
    var fold: ClosedRange<CGFloat>?
}

#if os(iOS)
extension GeometryProxy {
    /// The vertical fold's horizontal extent in this proxy's space. Inactive
    /// folds count too, so the panes don't jump while the device opens.
    func verticalFold() -> ClosedRange<CGFloat>? {
        guard #available(iOS 27.1, *) else { return nil }
        let fold = reservedRegions(kind: .division, options: .includeInactive)
            .map(\.frame)
            .first { $0.height > $0.width && $0.minX > 0 && $0.maxX < size.width }
        guard let fold else { return nil }
        return fold.minX...fold.maxX
    }
}

extension EnvironmentValues {
    /// True inside a pane of the unfolded iPhone Duo, for the few screens
    /// whose bar does not fit beside the status bar there.
    @Entry var isUnfoldedPane = false
}

extension View {
    /// iOS 27.1 can move a stack's back button into a vertical bar on its
    /// trailing edge, which in a pane lands beside the fold with the title
    /// still leading. A pane keeps the phone's horizontal bar. Folded, the
    /// system default is unchanged.
    @ViewBuilder
    func horizontalToolbarInPane(_ isPane: Bool) -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(isPane ? .disabled : .automatic)
        } else {
            self
        }
    }

    /// In a pane the trailing status bar leaves the navigation bar too little
    /// room for a long title beside two buttons, so the screen drops the bar
    /// title and shows it in its own content instead. Folded, unchanged.
    @ViewBuilder
    func barTitleInContent(_ isPane: Bool) -> some View {
        if #available(iOS 18, *) {
            toolbar(removing: isPane ? .title : nil)
        } else {
            self
        }
    }

    /// A pane is only phone-height, so the floating tab bar always sits over
    /// some of the leading pane's rows. Ending the list in a fade above the bar
    /// sliced the row sitting on it; letting it run on showed rows crisp around
    /// and below the glass. In a pane, a tab's rows still run under the bar to
    /// the display edge (and the last one still scrolls clear, as on a phone),
    /// but from just above the bar they are blurred and washed toward the
    /// background, so they read as depth, not text. The wash matches the band
    /// under the fold, so the blur never ends in an edge there. Folded it is
    /// invisible and the phone layout is untouched; it stays in both poses so
    /// folding never rebuilds the tab.
    func blursUnderTabBar(_ isPane: Bool) -> some View {
        // The lead-in lifts the last row clear of the blur too, not just of the bar.
        contentMargins(.bottom, isPane ? TabBarEdgeBlur.leadIn : 0, for: .scrollContent)
            .overlay {
                GeometryReader { proxy in
                    let blur = TabBarEdgeBlur(bottomInset: proxy.safeAreaInsets.bottom)
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay { Color(uiColor: .systemGroupedBackground).opacity(0.6) }
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: blur.fullStrengthAt),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        }
                        .frame(height: blur.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .ignoresSafeArea(.container, edges: .bottom)
                }
                .opacity(isPane ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}
#endif
