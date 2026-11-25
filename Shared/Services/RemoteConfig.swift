import Foundation

/// What RevenueCat can change without a release, read from the current
/// offering's metadata, so a running RevenueCat Experiment's variant is what
/// gets read. Every variant ships in the binary, and a missing, non-string or
/// unknown value is the control, which is exactly what 1.0.7 shipped.
///
/// Keys a switch reads must be set the same on every offering, or an
/// Experiment arm would flip them as a side effect.
///
/// DEBUG builds can pin any key for captures: `-elderhub.rc.<key> <value>`.
enum RemoteConfig {
    /// The value for `key`, or `fallback` when it is missing, not a string,
    /// or not one of the shipped variants.
    static func value<T: RawRepresentable>(
        _ key: String,
        in metadata: [String: Any]?,
        default fallback: T
    ) -> T where T.RawValue == String {
        #if DEBUG
        if let pinned = launchOverride(key).flatMap(T.init(rawValue:)) { return pinned }
        #endif
        guard let raw = metadata?[key] as? String else { return fallback }
        return T(rawValue: raw) ?? fallback
    }

    /// On unless the metadata says exactly "off".
    static func isOn(_ remoteSwitch: RemoteSwitch, in metadata: [String: Any]?) -> Bool {
        #if DEBUG
        if let pinned = launchOverride(remoteSwitch.rawValue) { return pinned != "off" }
        #endif
        return (metadata?[remoteSwitch.rawValue] as? String) != "off"
    }

    #if DEBUG
    private static func launchOverride(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-elderhub.rc.\(key)"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    #endif
}

/// Remote off switches, for what is worth pausing without a release.
enum RemoteSwitch: String, CaseIterable, Sendable {
    /// Apple's rating prompt after everything on Today is done.
    case ratingPrompt = "rating_prompt"
}

/// The paywall's trial button wording. The paywall is the only trial button
/// in the app (onboarding has no trial page), and it uses title case.
enum TrialCTA: String, CaseIterable, Sendable {
    static let metadataKey = "trial_cta"

    /// Control: "Start My 7-Day Free Trial", as shipped. The number is the
    /// store's own trial length, so it follows the offer in App Store Connect.
    case sevenDay = "seven_day"
    case my
    case your

    static func from(metadata: [String: Any]?) -> TrialCTA {
        RemoteConfig.value(metadataKey, in: metadata, default: .sevenDay)
    }

    /// The button title when this Apple ID would be granted `trialDays`.
    func title(trialDays: Int) -> String {
        switch self {
        case .sevenDay: return "Start My \(trialDays)-Day Free Trial"
        case .my: return "Start My Free Trial"
        case .your: return "Start Your Free Trial"
        }
    }

    /// The paywall button for the selected plan. An account with no trial to
    /// take is never promised one (3.1.2), whatever the arm, and keeps the
    /// wording it always had.
    func buttonTitle(trialDays: Int?, period: PlanPeriod) -> String {
        if let trialDays { return title(trialDays: trialDays) }
        if period == .lifetime { return "Unlock Lifetime" }
        return "Subscribe"
    }
}
