import Foundation

/// Persists rating-ask eligibility. The ask itself is the system
/// `requestReview()` with no question in front of it (App Review 5.6.1).
///
/// This is a Medical-category app opened by people who are worried, so the
/// moment matters: Today asks only after a dose, task or bill was just marked
/// done and nothing is outstanding for anyone. The recipient's phone renders
/// `CheckInHomeView` and never reaches Today. Nothing here leaves the device.
@MainActor
enum ReviewPrompt {
    /// What the user did about a review. Only opening the review page ends the
    /// passive asks: someone who sent feedback can still rate.
    enum Outcome: String {
        case openedWriteReview
        /// Emailed support. Never stops the asks.
        case submittedFeedback
    }

    private static let defaults = UserDefaults.standard

    private enum Key {
        static let launchCount = "reviewPrompt.launchCount"
        static let lastShownDate = "reviewPrompt.lastShownDate"
        static let outcome = "reviewPrompt.outcome"
        static let pendingPositiveMoment = "reviewPrompt.pendingPositiveMoment"
        /// Written by the old in-app rating sheet. Read only as a cooldown
        /// fallback so an upgrade doesn't ask again right away.
        static let legacyLastAsked = "reviewPrompt.lastAsked"
        static let legacyUnused = [
            "reviewPrompt.firstOpen", "reviewPrompt.settled", "reviewPrompt.softDefer",
            "reviewPrompt.activeDayCount", "reviewPrompt.lastActiveDay",
        ]
    }

    /// Ask early. The only tenure gate is "not the first session": a second cold start.
    static let minimumLaunchCount = 2
    /// Days between our calls. Apple shows the prompt at most three times a
    /// year per device and decides each time, so this paces our asks.
    static let cooldownDays = 30

    /// UI tests and the Duo screenshot tour never count launches or ask.
    static var skipsAutomation: Bool {
        ProcessInfo.processInfo.arguments.contains {
            $0 == "-uitest-reset" || $0 == "-uitest-wipe-store" || $0 == "-rcfunnelprobe" || $0 == "-FASTLANE_SNAPSHOT"
                || $0 == "-DuoTour"
        }
    }

    // MARK: - State

    static var appLaunchCount: Int {
        get { max(defaults.integer(forKey: Key.launchCount), 0) }
        set { defaults.set(newValue, forKey: Key.launchCount) }
    }

    static var lastShownDate: Date? {
        get {
            defaults.object(forKey: Key.lastShownDate) as? Date
                ?? defaults.object(forKey: Key.legacyLastAsked) as? Date
        }
        set {
            defaults.removeObject(forKey: Key.legacyLastAsked)
            if let newValue {
                defaults.set(newValue, forKey: Key.lastShownDate)
            } else {
                defaults.removeObject(forKey: Key.lastShownDate)
            }
        }
    }

    static var outcome: Outcome? {
        get { defaults.string(forKey: Key.outcome).flatMap(Outcome.init(rawValue:)) }
        set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: Key.outcome)
            } else {
                defaults.removeObject(forKey: Key.outcome)
            }
        }
    }

    static var hasPendingPositiveMoment: Bool {
        get { defaults.bool(forKey: Key.pendingPositiveMoment) }
        set { defaults.set(newValue, forKey: Key.pendingPositiveMoment) }
    }

    // MARK: - Recording

    static func recordAppLaunch() {
        Key.legacyUnused.forEach(defaults.removeObject(forKey:))
        guard !skipsAutomation else { return }
        appLaunchCount += 1
    }

    /// A dose taken, a task done or a bill paid.
    static func recordPositiveMoment() {
        guard !skipsAutomation else { return }
        hasPendingPositiveMoment = true
    }

    // MARK: - Eligibility

    static func passivePromptAllowed(now: Date = .now) -> Bool {
        guard outcome != .openedWriteReview else { return false }
        guard let last = lastShownDate else { return true }
        return now.timeIntervalSince(last) >= TimeInterval(cooldownDays) * 86_400
    }

    static func canRequestReview(hasCompletedSetup: Bool, now: Date = .now) -> Bool {
        guard !skipsAutomation, hasCompletedSetup, passivePromptAllowed(now: now) else { return false }
        return appLaunchCount >= minimumLaunchCount
    }

    static func shouldRequestAfterPositiveMoment(hasCompletedSetup: Bool, now: Date = .now) -> Bool {
        guard hasPendingPositiveMoment else { return false }
        return canRequestReview(hasCompletedSetup: hasCompletedSetup, now: now)
    }

    // MARK: - Outcomes

    static func markShown(now: Date = .now) {
        lastShownDate = now
        hasPendingPositiveMoment = false
    }

    static func markOpenedWriteReview() {
        outcome = .openedWriteReview
        markShown()
    }

    /// Never overwrites `.openedWriteReview`: feedback sent after the review
    /// page must not reopen the asks that page ended.
    static func markFeedbackSubmitted() {
        if outcome != .openedWriteReview {
            outcome = .submittedFeedback
        }
    }
}
