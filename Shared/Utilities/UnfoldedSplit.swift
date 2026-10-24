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

/// Where the tabs go. Folded, and on every other iPhone, they are the system's
/// floating bar at the bottom. A pane is only phone-height, so a bar at its
/// bottom always sat over the leading list's last rows: fading the list out
/// above it sliced the row on it, and blurring rows under it still left one
/// half covered (visual review, 2026-10-23). Split, the same tabs run as a
/// strip across the top of the leading pane instead, and both panes' lists
/// run off the display's bottom edge, as any scrolling list does.
struct PaneTabChrome: Equatable, Sendable {
    /// Where iOS 27.1 centres a pane's bar row on the inner display, in the
    /// status band (measured on the trailing pane's back button). The strip
    /// is centred on it, so both panes' top rows line up.
    static let navigationRowCenter: CGFloat = 48
    static let capsuleHeight: CGFloat = 46
    /// The strip's top, from the display's top edge.
    static let stripTop: CGFloat = navigationRowCenter - capsuleHeight / 2
    /// How far below the top safe edge the TabView starts while split. Not
    /// touching the edge is what drops each tab's own bar row out of the
    /// status band, below the strip.
    static let splitContentInset: CGFloat = 12

    var contentInset: CGFloat
    var showsSystemTabBar: Bool

    init(split: UnfoldedSplit?) {
        contentInset = split == nil ? 0 : Self.splitContentInset
        showsSystemTabBar = split == nil
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

    /// Split, the strip at the top of the leading pane replaces the system
    /// tab bar. Folded the system default stays.
    @ViewBuilder
    func systemTabBarHidden(_ isHidden: Bool) -> some View {
        if #available(iOS 18, *) {
            toolbarVisibility(isHidden ? .hidden : .automatic, for: .tabBar)
        } else {
            toolbar(isHidden ? .hidden : .automatic, for: .tabBar)
        }
    }
}
#endif
