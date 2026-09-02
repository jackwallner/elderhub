import Foundation

/// When it is fair to ask this person what they think of Elderhub.
///
/// The app had no rating request, no Settings entry and no feedback route at
/// all, which in this category is not a small omission: the eldercare shelf has
/// no search demand to speak of, so what a stranger has to go on is the rating
/// count, and a handful of ratings is the difference between the top of the
/// category and invisible.
///
/// The care this needs is the other half. This is a Medical-category app opened
/// by people who are worried, and an "enjoying the app?" card in front of an
/// overdue dose is worse than never asking: it is the app talking about itself
/// while somebody is trying to find out whether their mother took her tablets.
/// So the gate here is deliberately narrow, and the checks that matter are the
/// negative ones:
///
/// - Never while anything is outstanding for anyone today (`isQuietDay`).
/// - Never on the recipient's screen. Eleanor is handed this phone to press one
///   button; she is not the person with an opinion about the app, and asking
///   her for a rating she cannot leave is noise at best.
/// - Never during onboarding, and never before the app has actually been used
///   across several days.
///
/// Nothing here leaves the device and nothing is sent anywhere.
@MainActor
enum ReviewPrompt {
    private static let defaults = UserDefaults.standard

    private static let firstOpenKey = "reviewPrompt.firstOpen"
    private static let lastAskedKey = "reviewPrompt.lastAsked"
    private static let settledKey = "reviewPrompt.settled"
    private static let softDeferKey = "reviewPrompt.softDefer"
    private static let activeDayCountKey = "reviewPrompt.activeDayCount"
    private static let lastActiveDayKey = "reviewPrompt.lastActiveDay"

    /// Distinct days on which the caregiver actually recorded something before
    /// the question is fair. A week of real use is the honest signal that this
    /// app is part of somebody's routine, and it is a much better one than
    /// launch count, which counts opening the app and closing it again in
    /// frustration.
    static let requiredActiveDays = 5
    /// Days since first open, so a burst of activity in one afternoon does not
    /// qualify.
    static let requiredDaysSinceFirstOpen = 3
    /// After a "Not now".
    static let cooldownDays = 60
    /// After a yes that led to Apple's own prompt, which frequently shows
    /// nothing at all. A long jail there burns the ask on a dialog the user
    /// never saw.
    static let softDeferCooldownDays = 30

    // MARK: Recording

    static func recordAppLaunch(now: Date = .now) {
        if defaults.object(forKey: firstOpenKey) == nil {
            defaults.set(now, forKey: firstOpenKey)
        }
    }

    /// Called when the caregiver records something real: a dose, a task, a
    /// bill. Counts the day, not the action, so a busy Monday is one day.
    static func recordActiveDay(now: Date = .now) {
        let today = Calendar.current.startOfDay(for: now)
        if let last = defaults.object(forKey: lastActiveDayKey) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) {
            return
        }
        defaults.set(today, forKey: lastActiveDayKey)
        defaults.set(activeDayCount + 1, forKey: activeDayCountKey)
    }

    static var activeDayCount: Int {
        max(defaults.integer(forKey: activeDayCountKey), 0)
    }

    // MARK: Eligibility

    /// `isQuietDay` is the caller's answer to "is there anything outstanding
    /// for anyone right now". It is passed in rather than computed here so this
    /// type stays free of the model layer and stays testable.
    static func shouldAsk(isQuietDay: Bool, now: Date = .now) -> Bool {
        guard !isSettled else { return false }
        guard isQuietDay else { return false }
        guard activeDayCount >= requiredActiveDays else { return false }
        guard let first = defaults.object(forKey: firstOpenKey) as? Date else { return false }
        guard now.timeIntervalSince(first) >= TimeInterval(requiredDaysSinceFirstOpen) * 86_400 else {
            return false
        }
        guard let last = defaults.object(forKey: lastAskedKey) as? Date else { return true }
        let days = defaults.bool(forKey: softDeferKey) ? softDeferCooldownDays : cooldownDays
        return now.timeIntervalSince(last) >= TimeInterval(days) * 86_400
    }

    /// True once the reader has answered in a way that should not be asked
    /// again: they went to the App Store, or they sent feedback.
    static var isSettled: Bool { defaults.bool(forKey: settledKey) }

    // MARK: Outcomes

    static func markAsked(now: Date = .now) {
        defaults.set(now, forKey: lastAskedKey)
        defaults.set(false, forKey: softDeferKey)
    }

    /// Said yes, so Apple's prompt was raised. It may have shown nothing, hence
    /// the shorter cooldown.
    static func markSoftDeferred(now: Date = .now) {
        defaults.set(now, forKey: lastAskedKey)
        defaults.set(true, forKey: softDeferKey)
    }

    static func markSettled(now: Date = .now) {
        defaults.set(true, forKey: settledKey)
        defaults.set(now, forKey: lastAskedKey)
    }

    /// Test seam. Also what Settings' "Rate Elderhub" implicitly bypasses: a
    /// deliberate tap is never gated.
    static func resetForTesting() {
        for key in [firstOpenKey, lastAskedKey, settledKey, softDeferKey,
                    activeDayCountKey, lastActiveDayKey] {
            defaults.removeObject(forKey: key)
        }
    }
}
