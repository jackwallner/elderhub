import Foundation
import Testing

@testable import Aging

/// The gate on asking somebody what they think of a Medical-category app.
///
/// The negative cases are the ones that matter. Asking at the wrong moment
/// here is not a minor annoyance: it is the app talking about itself in front
/// of an overdue dose.
@MainActor
struct ReviewPromptTests {

    private func fresh() {
        ReviewPrompt.resetForTesting()
    }

    @Test func neverAsksOnADayWithAnythingOutstanding() {
        fresh()
        let longAgo = Date().addingTimeInterval(-30 * 86_400)
        ReviewPrompt.recordAppLaunch(now: longAgo)
        for day in 0..<ReviewPrompt.requiredActiveDays {
            ReviewPrompt.recordActiveDay(now: longAgo.addingTimeInterval(Double(day) * 86_400))
        }

        #expect(ReviewPrompt.shouldAsk(isQuietDay: false) == false)
        #expect(ReviewPrompt.shouldAsk(isQuietDay: true))
    }

    @Test func neverAsksBeforeTheAppHasBeenUsedAcrossSeveralDays() {
        fresh()
        let longAgo = Date().addingTimeInterval(-30 * 86_400)
        ReviewPrompt.recordAppLaunch(now: longAgo)

        // One busy afternoon is not a routine.
        ReviewPrompt.recordActiveDay(now: longAgo)
        #expect(ReviewPrompt.shouldAsk(isQuietDay: true) == false)

        for day in 1..<ReviewPrompt.requiredActiveDays {
            ReviewPrompt.recordActiveDay(now: longAgo.addingTimeInterval(Double(day) * 86_400))
        }
        #expect(ReviewPrompt.shouldAsk(isQuietDay: true))
    }

    /// The day is counted, not the tap. A caregiver who ticks off six doses
    /// before breakfast has had one day of using the app, not six.
    @Test func manyActionsInOneDayCountOnce() {
        fresh()
        let today = Date()
        for _ in 0..<12 {
            ReviewPrompt.recordActiveDay(now: today)
        }
        #expect(ReviewPrompt.activeDayCount == 1)
    }

    @Test func neverAsksInTheFirstFewDaysHoweverBusyTheyWere() {
        fresh()
        let now = Date()
        ReviewPrompt.recordAppLaunch(now: now)
        for day in 0..<ReviewPrompt.requiredActiveDays {
            ReviewPrompt.recordActiveDay(now: now.addingTimeInterval(Double(day) * 3_600))
        }

        #expect(ReviewPrompt.shouldAsk(isQuietDay: true, now: now) == false)
    }

    @Test func aNotNowIsRespectedForTheCooldown() {
        fresh()
        let longAgo = Date().addingTimeInterval(-90 * 86_400)
        ReviewPrompt.recordAppLaunch(now: longAgo)
        for day in 0..<ReviewPrompt.requiredActiveDays {
            ReviewPrompt.recordActiveDay(now: longAgo.addingTimeInterval(Double(day) * 86_400))
        }

        let asked = Date()
        ReviewPrompt.markAsked(now: asked)

        let tomorrow = asked.addingTimeInterval(86_400)
        #expect(ReviewPrompt.shouldAsk(isQuietDay: true, now: tomorrow) == false)

        let afterCooldown = asked.addingTimeInterval(
            TimeInterval(ReviewPrompt.cooldownDays + 1) * 86_400
        )
        #expect(ReviewPrompt.shouldAsk(isQuietDay: true, now: afterCooldown))
    }

    /// Saying yes raises Apple's prompt, which often shows nothing at all. A
    /// full cooldown there would spend the ask on a dialog nobody saw.
    @Test func sayingYesUsesTheShorterCooldown() {
        fresh()
        let longAgo = Date().addingTimeInterval(-120 * 86_400)
        ReviewPrompt.recordAppLaunch(now: longAgo)
        for day in 0..<ReviewPrompt.requiredActiveDays {
            ReviewPrompt.recordActiveDay(now: longAgo.addingTimeInterval(Double(day) * 86_400))
        }

        let asked = Date()
        ReviewPrompt.markSoftDeferred(now: asked)

        let betweenCooldowns = asked.addingTimeInterval(
            TimeInterval(ReviewPrompt.softDeferCooldownDays + 1) * 86_400
        )
        #expect(ReviewPrompt.shouldAsk(isQuietDay: true, now: betweenCooldowns))
    }

    @Test func onceSettledItNeverAsksAgain() {
        fresh()
        let longAgo = Date().addingTimeInterval(-400 * 86_400)
        ReviewPrompt.recordAppLaunch(now: longAgo)
        for day in 0..<ReviewPrompt.requiredActiveDays {
            ReviewPrompt.recordActiveDay(now: longAgo.addingTimeInterval(Double(day) * 86_400))
        }

        ReviewPrompt.markSettled(now: longAgo)

        let muchLater = Date().addingTimeInterval(365 * 86_400)
        #expect(ReviewPrompt.isSettled)
        #expect(ReviewPrompt.shouldAsk(isQuietDay: true, now: muchLater) == false)
    }
}
