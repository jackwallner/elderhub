import Testing
import Foundation
@testable import Aging
/// The fleet paywall record, checked in this app's own build.
///
/// The `rc-funnel-probe` run proves an impression reaches RevenueCat. These
/// prove what is underneath it: the counts, the conversion freeze, RevenueCat's
/// silent 40-character key limit, and the rule that nothing here may carry free
/// text or health data. Every assertion is a claim that will be read off a
/// customer record later, so a wrong value is worse than no value.

@MainActor
struct PaywallFunnelTests {

    /// A throwaway suite per test. These counters outlive a launch and would
    /// otherwise carry between tests and into the real container.
    private func withFreshSuite(_ body: () throws -> Void) rethrows {
        let name = "conv.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        ConversionDiagnostics.defaultsOverride = suite
        defer {
            ConversionDiagnostics.defaultsOverride = nil
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        try body()
    }

    @Test func countsPitchesPerSurfaceAndInTotal() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordPitchView(impressionID: "elderhub_paywall")
            ConversionDiagnostics.recordPitchView(impressionID: "elderhub_paywall")
            ConversionDiagnostics.recordPitchView(impressionID: "elderhub_settings")
            let a = ConversionDiagnostics.subscriberAttributes
            #expect(a["pitch_views_total"] == "3")
            #expect(a["pitch_views_paywall"] == "2")
            #expect(a["pitch_last"] == "settings")
        }
    }

    @Test func noAttributesBeforeAnyPitchIsSeen() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordAppOpen()
            #expect(ConversionDiagnostics.subscriberAttributes.isEmpty)
        }
    }

    @Test func recordsHowEarlyTheFirstPitchArrived() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordAppOpen()
            ConversionDiagnostics.recordAppOpen()
            ConversionDiagnostics.recordPitchView(impressionID: "elderhub_paywall")
            let a = ConversionDiagnostics.subscriberAttributes
            #expect(a["opens_before_first_pitch"] == "2")
            #expect(a["days_since_install"] == "0")
        }
    }

    @Test func theEarlinessPairIsFrozenOnTheFirstPitchOnly() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordAppOpen()
            ConversionDiagnostics.recordPitchView(impressionID: "elderhub_paywall")
            ConversionDiagnostics.recordAppOpen()
            ConversionDiagnostics.recordPitchView(impressionID: "elderhub_settings")
            #expect(ConversionDiagnostics.subscriberAttributes["opens_before_first_pitch"] == "1")
        }
    }

    @Test func anInstallThatPredatesThisCodeReportsNoAge() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordPitchView(impressionID: "elderhub_paywall")
            let a = ConversionDiagnostics.subscriberAttributes
            #expect(a["days_since_install"] == nil)
            #expect(a["pitch_views_total"] == "1")
        }
    }

    @Test func conversionFreezesTheSurfaceAndCountAtTheMomentOfSale() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordPitchView(impressionID: "elderhub_paywall")
            ConversionDiagnostics.recordPitchView(impressionID: "elderhub_settings")
            ConversionDiagnostics.recordConversion(plan: "yearly", startedTrial: true, offeringID: "default")
            ConversionDiagnostics.recordPitchView(impressionID: "elderhub_paywall")
            let a = ConversionDiagnostics.subscriberAttributes
            #expect(a["converted_surface"] == "settings")
            #expect(a["pitch_views_at_convert"] == "2")
            #expect(a["converted_with_trial"] == "true")
            #expect(a["converted_offering"] == "default")
        }
    }

    @Test func onlyTheFirstConversionIsRecorded() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordPitchView(impressionID: "elderhub_paywall")
            ConversionDiagnostics.recordConversion(plan: "monthly", startedTrial: true)
            ConversionDiagnostics.recordConversion(plan: "yearly", startedTrial: false)
            let a = ConversionDiagnostics.subscriberAttributes
            #expect(a["converted_plan"] == "monthly")
            #expect(a["converted_with_trial"] == "true")
        }
    }

    @Test func attributeKeysStayInsideRevenueCatsLimit() throws {
        try withFreshSuite {
            let long = String(repeating: "a", count: 80)
            ConversionDiagnostics.recordPitchView(impressionID: "elderhub_\(long)")
            for key in ConversionDiagnostics.subscriberAttributes.keys {
                #expect(key.count <= 40, "attribute key too long: \(key)")
            }
        }
    }

    @Test func noAttributeCarriesFreeTextOrHealthData() throws {
        try withFreshSuite {
            ConversionDiagnostics.recordAppOpen()
            ConversionDiagnostics.recordPitchView(impressionID: "elderhub_paywall")
            ConversionDiagnostics.recordConversion(plan: "monthly", startedTrial: false)
            for (key, value) in ConversionDiagnostics.subscriberAttributes {
                #expect(!value.contains(" "), "\(key) looks like free text: \(value)")
                #expect(value.count <= 64, "\(key) is too long to be a label")
            }
        }
    }
}
