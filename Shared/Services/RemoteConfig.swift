import Foundation
@preconcurrency import RevenueCat

/// What RevenueCat can change without a release, read from the current
/// offering's metadata (so a running Experiment's variant is what is read).
/// Every variant ships in the binary, and a missing or unknown value is the
/// control, which is the copy the app shipped before this reader existed.
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

    /// On unless the metadata says "off".
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

/// Things worth pausing without a release.
enum RemoteSwitch: String, CaseIterable, Sendable {
    /// Apple's rating prompt after Today is all done.
    case ratingPrompt = "rating_prompt"
}

/// The paywall's trial button wording. The only trial button in the app.
enum TrialCTA: String, CaseIterable, Sendable {
    static let metadataKey = "trial_cta"

    /// Control: "Start My 7-Day Free Trial", the button as shipped, with the
    /// length the App Store says this plan's trial runs.
    case sevenDay = "seven_day"
    case my
    case your

    static func from(metadata: [String: Any]?) -> TrialCTA {
        RemoteConfig.value(metadataKey, in: metadata, default: .sevenDay)
    }

    func title(trialDays days: Int) -> String {
        switch self {
        case .sevenDay: return "Start My \(days)-Day Free Trial"
        case .my: return "Start My Free Trial"
        case .your: return "Start Your Free Trial"
        }
    }

    /// The paywall's main button. `trialDays` is nil unless this Apple
    /// Account would really be granted the trial, so an account that already
    /// used it is never promised one (3.1.2) and sees the shipped wording.
    func buttonTitle(period: PlanPeriod?, trialDays: Int?, isPurchasing: Bool) -> String {
        guard let period else { return "Continue" }
        if isPurchasing { return "Working…" }
        if let trialDays { return title(trialDays: trialDays) }
        if period == .lifetime { return "Unlock Lifetime" }
        return "Subscribe"
    }
}

extension StoreService {
    private var remoteMetadata: [String: Any]? { offerings?.current?.metadata }

    var trialCTA: TrialCTA { TrialCTA.from(metadata: remoteMetadata) }

    func isOn(_ remoteSwitch: RemoteSwitch) -> Bool {
        RemoteConfig.isOn(remoteSwitch, in: remoteMetadata)
    }
}
