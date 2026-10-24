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

    /// A pane is only phone-height, so the floating tab bar sat over the
    /// leading pane's last visible rows and they showed through its glass.
    /// In a pane, a tab's content fades out just above its bottom safe-area
    /// edge (the top of the tab bar) and the bar floats over plain
    /// background. Folded, the mask covers everything and the phone layout is
    /// untouched; the mask stays in both poses so folding never rebuilds the
    /// tab.
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

    func endsAboveTabBar(_ isPane: Bool) -> some View {
        mask {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: isPane ? 16 : 0)
            }
            .ignoresSafeArea(.all, edges: isPane ? [.top, .horizontal] : .all)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}
#endif
