import Foundation
import Testing

@testable import Aging

/// The offering-metadata reader and the trial button wording it picks.
struct RemoteConfigTests {
    // MARK: Reader

    @Test func missingNonStringAndUnknownValuesAreTheControl() {
        #expect(TrialCTA.from(metadata: nil) == .sevenDay)
        #expect(TrialCTA.from(metadata: [:]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": 1]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": true]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": "their"]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": "MY"]) == .sevenDay)
    }

    @Test func eachKnownValueIsItsArm() {
        #expect(TrialCTA.from(metadata: ["trial_cta": "seven_day"]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": "my"]) == .my)
        #expect(TrialCTA.from(metadata: ["trial_cta": "your"]) == .your)
        #expect(TrialCTA.metadataKey == "trial_cta")
    }

    @Test func switchesAreOnUnlessTheValueIsOff() {
        #expect(RemoteConfig.isOn(.ratingPrompt, in: nil))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: [:]))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "on"]))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": false]))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "OFF"]))
        #expect(!RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "off"]))
        #expect(RemoteSwitch.ratingPrompt.rawValue == "rating_prompt")
    }

    // MARK: Wording

    /// Character for character what the paywall button said before the
    /// reader existed, for every trial length the store can hand back.
    @Test func controlIsTheShippedButton() {
        for days in [3, 7, 14, 30] {
            #expect(TrialCTA.sevenDay.title(trialDays: days) == "Start My \(days)-Day Free Trial")
        }
    }

    @Test func eachArmHasItsTitle() {
        #expect(TrialCTA.my.title(trialDays: 7) == "Start My Free Trial")
        #expect(TrialCTA.your.title(trialDays: 7) == "Start Your Free Trial")
    }

    /// No trial promise to an account that already used it (3.1.2): every arm
    /// falls back to the shipped wording.
    @Test func ineligibleWordingIsUnchanged() {
        for arm in TrialCTA.allCases {
            #expect(arm.buttonTitle(period: .yearly, trialDays: nil, isPurchasing: false) == "Subscribe")
            #expect(arm.buttonTitle(period: .monthly, trialDays: nil, isPurchasing: false) == "Subscribe")
            #expect(arm.buttonTitle(period: .lifetime, trialDays: nil, isPurchasing: false) == "Unlock Lifetime")
            #expect(arm.buttonTitle(period: nil, trialDays: 7, isPurchasing: false) == "Continue")
            #expect(arm.buttonTitle(period: .yearly, trialDays: 7, isPurchasing: true) == "Working…")
        }
        #expect(TrialCTA.sevenDay.buttonTitle(period: .yearly, trialDays: 7, isPurchasing: false)
            == "Start My 7-Day Free Trial")
        #expect(TrialCTA.your.buttonTitle(period: .monthly, trialDays: 7, isPurchasing: false)
            == "Start Your Free Trial")
    }
}
