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
    /// How far above the bar the blur begins to build.
    static let leadIn: CGFloat = 28
    /// The share of the pane's width over which the blur fades out toward
    /// the fold, so it never ends in an edge against the band between panes.
    static let foldFade: CGFloat = 0.12

    var bottomInset: CGFloat

    /// From the first blurred row to the display's bottom edge.
    var height: CGFloat { max(bottomInset, 0) + Self.leadIn }

    /// Where, from the band's top (0) to the display edge (1), the blur
    /// reaches full strength: the bar's top edge.
    var fullStrengthAt: CGFloat { Self.leadIn / height }
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
    /// some of the leading pane's rows. Ending the list above the bar sliced a
    /// row at a fade; letting it run on showed the rows crisp around and below
    /// the glass. In a pane, a tab's rows still run under the bar to the
    /// display edge (and the last one still scrolls clear, as on a phone), but
    /// a thin material starts `TabBarEdgeBlur.leadIn` above the bar, is at
    /// full strength by its top edge and fades out before the fold. Folded it
    /// is invisible and the phone layout is untouched; it stays in both poses
    /// so folding never rebuilds the tab.
    func blursUnderTabBar(_ isPane: Bool) -> some View {
        // The lead-in lifts the last row clear of the blur too, not just of the bar.
        contentMargins(.bottom, isPane ? TabBarEdgeBlur.leadIn : 0, for: .scrollContent)
            .overlay {
                GeometryReader { proxy in
                    let blur = TabBarEdgeBlur(bottomInset: proxy.safeAreaInsets.bottom)
                    Rectangle()
                        .fill(.thinMaterial)
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: blur.fullStrengthAt),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        }
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 1 - TabBarEdgeBlur.foldFade),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .leading, endPoint: .trailing
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
