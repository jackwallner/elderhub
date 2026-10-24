import CoreGraphics
import Testing

@testable import Aging

/// The unfolded iPhone Duo puts the tabs and Care on either side of the fold.
/// Every other shape must keep the phone layout, and a split must never leave
/// a pane too narrow for it or a gap the panes do not cover.
struct UnfoldedSplitTests {
    /// The unfolded iPhone Duo's inner display, held landscape.
    private let innerWidth: CGFloat = 951

    @Test func compactWidthNeverSplits() {
        #expect(UnfoldedSplit.make(width: 466, isRegularWidth: false, fold: nil) == nil)
        #expect(UnfoldedSplit.make(width: innerWidth, isRegularWidth: false, fold: 455.5...495.5) == nil)
    }

    @Test func portraitUnfoldStaysSingleColumn() {
        // 669 pt wide: two 360 pt panes do not fit.
        #expect(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil) == nil)
    }

    @Test func panesMeetTheMeasuredFoldEdges() throws {
        // The division region the iOS 27.1 simulator reports for the inner display.
        let split = try #require(UnfoldedSplit.make(width: innerWidth, isRegularWidth: true, fold: 455.5...495.5))
        #expect(split.primaryWidth == 455.5)
        #expect(split.secondaryX == 495.5)
        #expect(split.secondaryWidth == 455.5)
    }

    @Test func zeroWidthFoldStillMeetsIt() throws {
        let split = try #require(UnfoldedSplit.make(width: innerWidth, isRegularWidth: true, fold: 475...475))
        #expect(split.primaryWidth == 475)
        #expect(split.secondaryX == 475)
        #expect(split.primaryWidth + split.secondaryWidth == innerWidth)
    }

    @Test func noFoldSplitsEvenly() throws {
        let split = try #require(UnfoldedSplit.make(width: innerWidth, isRegularWidth: true, fold: nil))
        #expect(split.primaryWidth == 475)
        #expect(split.secondaryX == 475)
        #expect(split.secondaryWidth == 476)
    }

    @Test func offCentreFoldFallsBackToAnEvenSplit() throws {
        // A fold that would leave the trailing pane under 360 pt is ignored.
        let split = try #require(UnfoldedSplit.make(width: 800, isRegularWidth: true, fold: 500...510))
        #expect(split.primaryWidth == 400)
        #expect(split.secondaryX == 400)
        #expect(split.secondaryWidth == 400)
    }

    @Test func everySplitKeepsBothPanesUsableAndCoversTheWidth() {
        for width in stride(from: CGFloat(600), through: 1400, by: 7) {
            guard let split = UnfoldedSplit.make(width: width, isRegularWidth: true, fold: nil) else {
                #expect(width < UnfoldedSplit.minimumPaneWidth * 2)
                continue
            }
            #expect(split.primaryWidth >= UnfoldedSplit.minimumPaneWidth)
            #expect(split.secondaryWidth >= UnfoldedSplit.minimumPaneWidth)
            #expect(split.secondaryX + split.secondaryWidth == width)
        }
    }

    @Test func edgeBlurStartsJustAboveTheTabBar() {
        // The leading pane's bottom inset on the inner display: bar plus margin.
        let blur = TabBarEdgeBlur(bottomInset: 79)
        #expect(blur.height == 79 + TabBarEdgeBlur.leadIn)
        // It starts only a few points above the bar, so the row on the bar
        // keeps its last line, and is full a little way into the bar.
        #expect(TabBarEdgeBlur.leadIn <= 8)
        let fullAboveEdge = blur.height * (1 - blur.fullStrengthAt)
        #expect(abs(fullAboveEdge - (79 - TabBarEdgeBlur.settle)) < 0.001)
        #expect(fullAboveEdge > 0 && fullAboveEdge < 79)
    }

    @Test func edgeBlurWithoutAnInsetIsOnlyTheLeadIn() {
        let blur = TabBarEdgeBlur(bottomInset: -4)
        #expect(blur.height == TabBarEdgeBlur.leadIn)
        #expect(blur.fullStrengthAt == 1)
    }
}

#if DEBUG
/// `-DuoScreen` captures one surface per launch, folded and unfolded.
struct DuoScreenRouteTests {
    @Test func splitRouteKeepsItsTabBesideCare() {
        let route = DuoScreenshotTour.Route("sharing+mom.tasks")
        #expect(route.tab == .family)
        #expect(route.person == "mom")
        #expect(route.screen == "tasks")
    }

    @Test func foldedRouteAboutAPersonOpensCare() {
        let route = DuoScreenshotTour.Route("today+mom.card").folded
        #expect(route.tab == .people)
        #expect(route.person == "mom")
        #expect(route.screen == "card")
    }

    @Test func hubRouteDropsOnlyTheScreen() {
        let hub = DuoScreenshotTour.Route("sharing+mom.tasks").hub
        #expect(hub.tab == .family)
        #expect(hub.person == "mom")
        #expect(hub.screen == nil)
    }

    @Test func foldedRouteWithoutAPersonKeepsItsTab() {
        #expect(DuoScreenshotTour.Route("sharing").folded.tab == .family)
    }
}
#endif
