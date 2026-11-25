import Foundation
import Testing

@testable import Aging

/// Offering metadata can change the trial button's wording and pause the
/// rating prompt without a release. Anything it does not recognise is the
/// control, which has to be exactly what shipped before the reader existed.
struct RemoteConfigTests {
    @Test func missingNonStringAndUnknownValuesAreTheControl() {
        #expect(TrialCTA.from(metadata: nil) == .sevenDay)
        #expect(TrialCTA.from(metadata: [:]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": 1]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": true]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": "ours"]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": "MY"]) == .sevenDay)
    }

    @Test func eachKnownValueReadsItsArm() {
        #expect(TrialCTA.from(metadata: ["trial_cta": "seven_day"]) == .sevenDay)
        #expect(TrialCTA.from(metadata: ["trial_cta": "my"]) == .my)
        #expect(TrialCTA.from(metadata: ["trial_cta": "your"]) == .your)
        #expect(TrialCTA.metadataKey == "trial_cta")
    }

    /// Character for character the title `PaywallView.ctaTitle` built
    /// before the reader: "Start My \(days)-Day Free Trial".
    @Test func theControlIsThePreChangeCopy() {
        #expect(TrialCTA.sevenDay.title(trialDays: 7) == "Start My 7-Day Free Trial")
        #expect(TrialCTA.sevenDay.buttonTitle(trialDays: 7, period: .yearly) == "Start My 7-Day Free Trial")
        #expect(TrialCTA.sevenDay.buttonTitle(trialDays: 7, period: .monthly) == "Start My 7-Day Free Trial")
        #expect(TrialCTA.sevenDay.title(trialDays: 14) == "Start My 14-Day Free Trial")
    }

    @Test func eachArmHasItsPaywallTitle() {
        #expect(TrialCTA.my.buttonTitle(trialDays: 7, period: .yearly) == "Start My Free Trial")
        #expect(TrialCTA.your.buttonTitle(trialDays: 7, period: .yearly) == "Start Your Free Trial")
    }

    /// No trial promise to an account that already used it (3.1.2), in any arm.
    @Test func ineligibleWordingIsUnchangedInEveryArm() {
        for arm in TrialCTA.allCases {
            #expect(arm.buttonTitle(trialDays: nil, period: .yearly) == "Subscribe")
            #expect(arm.buttonTitle(trialDays: nil, period: .monthly) == "Subscribe")
            #expect(arm.buttonTitle(trialDays: nil, period: .lifetime) == "Unlock Lifetime")
        }
    }

    @Test func aSwitchIsOnUnlessTheValueIsOff() {
        #expect(RemoteConfig.isOn(.ratingPrompt, in: nil))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: [:]))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "on"]))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "OFF"]))
        #expect(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": false]))
        #expect(!RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "off"]))
        #expect(RemoteSwitch.ratingPrompt.rawValue == "rating_prompt")
    }
}
