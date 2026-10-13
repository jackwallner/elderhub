import Foundation
import Testing

@testable import Aging

/// The rating-ask rules from the fleet policy: ask from the second launch,
/// wait out a 30-day cooldown, stop only when the user opened the review page,
/// and never let feedback stop or restart the asks.
@MainActor
@Suite(.serialized)
struct ReviewPromptTests {
    /// Snapshots and restores the tracker's persisted state so the suite
    /// doesn't leave a simulator install mid-ask.
    private func withCleanTracker(_ body: () -> Void) {
        let launches = ReviewPrompt.appLaunchCount
        let lastShown = ReviewPrompt.lastShownDate
        let outcome = ReviewPrompt.outcome
        let pending = ReviewPrompt.hasPendingPositiveMoment
        defer {
            ReviewPrompt.appLaunchCount = launches
            ReviewPrompt.lastShownDate = lastShown
            ReviewPrompt.outcome = outcome
            ReviewPrompt.hasPendingPositiveMoment = pending
        }
        ReviewPrompt.outcome = nil
        ReviewPrompt.lastShownDate = nil
        ReviewPrompt.hasPendingPositiveMoment = false
        body()
    }

    @Test func asksFromTheSecondSession() {
        withCleanTracker {
            ReviewPrompt.appLaunchCount = 2
            #expect(ReviewPrompt.canRequestReview(hasCompletedSetup: true))
        }
    }

    @Test func neverAsksInTheFirstSession() {
        withCleanTracker {
            ReviewPrompt.appLaunchCount = 1
            #expect(!ReviewPrompt.canRequestReview(hasCompletedSetup: true))
        }
    }

    @Test func stillRequiresSomeoneOnTheRecord() {
        withCleanTracker {
            ReviewPrompt.appLaunchCount = 9
            #expect(!ReviewPrompt.canRequestReview(hasCompletedSetup: false))
        }
    }

    @Test func openingTheReviewPageEndsTheAsks() {
        withCleanTracker {
            ReviewPrompt.appLaunchCount = 9
            ReviewPrompt.markOpenedWriteReview()
            ReviewPrompt.lastShownDate = Date.now.addingTimeInterval(-365 * 86_400)
            #expect(!ReviewPrompt.canRequestReview(hasCompletedSetup: true))
        }
    }

    @Test func waitsOutTheCooldown() {
        withCleanTracker {
            ReviewPrompt.appLaunchCount = 9
            ReviewPrompt.lastShownDate = Date.now.addingTimeInterval(-10 * 86_400)
            #expect(!ReviewPrompt.canRequestReview(hasCompletedSetup: true))
            ReviewPrompt.lastShownDate = Date.now.addingTimeInterval(-31 * 86_400)
            #expect(ReviewPrompt.canRequestReview(hasCompletedSetup: true))
        }
    }

    @Test func feedbackNeverEndsTheAsks() {
        withCleanTracker {
            ReviewPrompt.appLaunchCount = 9
            ReviewPrompt.markFeedbackSubmitted()
            #expect(ReviewPrompt.outcome == .submittedFeedback)
            #expect(ReviewPrompt.lastShownDate == nil, "feedback must not start a cooldown")
            #expect(ReviewPrompt.canRequestReview(hasCompletedSetup: true))
        }
    }

    @Test func feedbackAfterTheReviewPageKeepsTheAsksEnded() {
        withCleanTracker {
            ReviewPrompt.appLaunchCount = 9
            ReviewPrompt.markOpenedWriteReview()
            ReviewPrompt.markFeedbackSubmitted()
            #expect(ReviewPrompt.outcome == .openedWriteReview)
            #expect(!ReviewPrompt.canRequestReview(hasCompletedSetup: true))
        }
    }

    /// A moment whose ask finds something outstanding or presented must
    /// survive that skip so the next dose marked can still ask.
    @Test func blockedAskKeepsTheMomentPending() {
        withCleanTracker {
            ReviewPrompt.appLaunchCount = 9
            ReviewPrompt.recordPositiveMoment()
            #expect(ReviewPrompt.shouldRequestAfterPositiveMoment(hasCompletedSetup: true))
            #expect(ReviewPrompt.shouldRequestAfterPositiveMoment(hasCompletedSetup: true))
            ReviewPrompt.markShown()
            #expect(!ReviewPrompt.shouldRequestAfterPositiveMoment(hasCompletedSetup: true))
        }
    }
}
