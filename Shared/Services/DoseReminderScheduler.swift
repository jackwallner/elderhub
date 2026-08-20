import Foundation
import OSLog
import SwiftData
import UserNotifications

// MARK: - Spec

/// One local notification we want iOS to be holding: a single medication, at a
/// single time of day, on a single weekday (or every day).
///
/// A value type on purpose. Everything that is hard about reminders (which
/// medications qualify, how a weekday list expands, which ones survive the 64
/// request budget) is decided over these, with no `UNUserNotificationCenter` in
/// sight, so it is all testable.
struct ReminderSpec: Hashable, Sendable, Identifiable {
    /// Every identifier this feature owns starts with this, which is what makes
    /// the diff safe: we only ever remove requests we scheduled ourselves and
    /// never touch the check-in reminder.
    static let identifierPrefix = "dose-"

    let medicationID: UUID
    let personName: String
    let medicationName: String
    let hour: Int
    let minute: Int
    /// `Calendar`'s 1-indexed, Sunday-first weekday. Nil means every day.
    let weekday: Int?

    var id: String { identifier }

    /// `dose-<medID>-<minutes>-<weekday>`, with `0` (not a valid `Calendar`
    /// weekday) standing in for every day. Derived entirely from the schedule,
    /// so rescheduling identical input produces identical identifiers and the
    /// diff is a no-op.
    var identifier: String {
        "\(Self.identifierPrefix)\(medicationID.uuidString)-\(hour * 60 + minute)-\(weekday ?? 0)"
    }

    /// Deliberately says whose dose it is. Every other med reminder on the App
    /// Store is single-user; "Mom: Metformin 500 mg" is the whole difference on
    /// a lock screen holding reminders for two parents.
    ///
    /// States a fact and stops. It never says what happens if the dose is
    /// missed, which would be a claim about a medical outcome (1.4.1).
    var body: String {
        personName.isEmpty ? medicationName : "\(personName): \(medicationName)"
    }

    var dateComponents: DateComponents {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        if let weekday { components.weekday = weekday }
        return components
    }
}

// MARK: - Planner

/// Turns medications into reminder specs. Pure, main-actor only because
/// SwiftData models are.
enum DoseReminderPlanner {

    /// iOS holds 64 pending local notifications per app and silently drops the
    /// rest. Three people x 6 medications x 3 times a day x specific weekdays is
    /// past it without anything looking wrong.
    static let deviceLimit = 64

    /// The daily check-in reminder is the one notification in this app that has
    /// to fire (`CheckInService`), so dose reminders never get to spend the last
    /// slot on the device.
    static let reservedRequests = 1

    /// The most dose reminders we will ever have pending.
    static let limit = deviceLimit - reservedRequests

    /// Every reminder that should exist for `people`, capped and in fire order.
    ///
    /// `date` is "now": it decides which specs are nearest and therefore which
    /// ones survive the cap. Rescheduling on foreground rolls that window
    /// forward, which is how a family bigger than 63 reminders still gets each
    /// one on the day it matters.
    @MainActor
    static func requests(
        for people: [Person],
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> [ReminderSpec] {
        var specs: [ReminderSpec] = []

        for person in people where person.deletedAt == nil {
            for medication in person.liveMedications where isEligible(medication, on: date, calendar: calendar) {
                for minutes in medication.scheduleMinutes.sorted() {
                    let hour = minutes / 60
                    let minute = minutes % 60
                    let weekdays: [Int?] = medication.weekdays.isEmpty
                        ? [nil]
                        : medication.weekdays.sorted().map { $0 }

                    for weekday in weekdays {
                        specs.append(
                            ReminderSpec(
                                medicationID: medication.id,
                                personName: person.displayLabel,
                                medicationName: medication.displayName,
                                hour: hour,
                                minute: minute,
                                weekday: weekday
                            )
                        )
                    }
                }
            }
        }

        return cap(specs, on: date, calendar: calendar)
    }

    /// A medication only earns a reminder if it is a live, timed prescription.
    private static func isEligible(_ medication: Medication, on date: Date, calendar: Calendar) -> Bool {
        guard medication.deletedAt == nil else { return false }
        guard medication.isActive, !medication.isAsNeeded else { return false }
        guard !medication.scheduleMinutes.isEmpty else { return false }
        if let endDate = medication.endDate, endDate < date { return false }
        return true
    }

    /// Sorts by next fire time and keeps the first `limit`. Ties break on the
    /// identifier so the same input always yields the same list, which is what
    /// lets the diff settle instead of churning on every foreground.
    static func cap(
        _ specs: [ReminderSpec],
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> [ReminderSpec] {
        let distant = Date.distantFuture
        let ordered = specs.sorted { lhs, rhs in
            let left = nextFireDate(for: lhs, after: date, calendar: calendar) ?? distant
            let right = nextFireDate(for: rhs, after: date, calendar: calendar) ?? distant
            if left != right { return left < right }
            return lhs.identifier < rhs.identifier
        }
        return Array(ordered.prefix(limit))
    }

    static func nextFireDate(
        for spec: ReminderSpec,
        after date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        calendar.nextDate(
            after: date,
            matching: spec.dateComponents,
            matchingPolicy: .nextTime
        )
    }
}

// MARK: - Per-device preference

/// Whether this phone wants reminders for a given person.
///
/// Device-local and deliberately not synced and not a migration: reminders are a
/// property of the phone in your pocket, not of the shared record. A daughter
/// who wants an 8am ping for Dad should not be forcing the same ping on her
/// brother two time zones away.
enum DoseReminderPreferences {
    private static let prefix = "dose-reminders."

    private static func key(_ personID: UUID) -> String {
        prefix + personID.uuidString
    }

    /// Off until asked for. Turning it on is the moment notification permission
    /// means something, which is the only moment this app asks for it.
    static func isEnabled(personID: UUID, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(personID))
    }

    static func setEnabled(_ enabled: Bool, personID: UUID, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key(personID))
    }

    static func clear(personID: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(personID))
    }
}

// MARK: - Scheduler

/// Diffs the reminders we want against the ones iOS is holding, and adds or
/// removes only the difference.
///
/// Nothing here talks to the network or to a group. A solo caregiver with no
/// account gets identical behaviour (I3), and the whole path works in airplane
/// mode (I1).
actor DoseReminderScheduler {
    static let shared = DoseReminderScheduler()

    private let log = Logger(subsystem: "com.jackwallner.aging", category: "dose-reminders")

    private init() {}

    /// The entry point every caller uses: read the people out of SwiftData on
    /// the main actor, hand the resulting value types off it.
    @MainActor
    static func refresh(in context: ModelContext, now: Date = Date()) async {
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        let enabled = people.filter { DoseReminderPreferences.isEnabled(personID: $0.id) }
        let specs = DoseReminderPlanner.requests(for: enabled, on: now)
        await shared.apply(specs)

        // Refill reminders share this actor's notification center and the
        // same 64-request device budget, so they only get whatever dose
        // reminders left behind.
        let refillSpecs = RefillReminderPlanner.requests(for: enabled, on: now)
        let refillBudget = max(0, DoseReminderPlanner.limit - specs.count)
        let refills = Array(refillSpecs.prefix(refillBudget))
        await shared.applyRefills(refills)

        // Appointments come last out of the same budget. They are the rarest of
        // the three and the ones a caregiver is least likely to have twenty of,
        // so taking whatever is left over costs nothing in practice.
        let appointmentSpecs = AppointmentReminderPlanner.requests(for: enabled, on: now)
        let appointmentBudget = max(0, DoseReminderPlanner.limit - specs.count - refills.count)
        await shared.applyAppointments(Array(appointmentSpecs.prefix(appointmentBudget)))
    }

    func apply(_ specs: [ReminderSpec]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(ReminderSpec.identifierPrefix) }

        // Permission can be revoked in Settings long after the toggles were set.
        // Clear ours out rather than leaving stale requests behind.
        guard await NotificationService.shared.isAuthorized() else {
            if !pending.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: pending)
            }
            return
        }

        let desired = Dictionary(specs.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let existing = Set(pending)

        let stale = existing.subtracting(desired.keys)
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }

        var added = 0
        for (identifier, spec) in desired where !existing.contains(identifier) {
            let content = UNMutableNotificationContent()
            content.title = "Time for a dose"
            content.body = spec.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: spec.dateComponents, repeats: true)
            )

            do {
                try await center.add(request)
                added += 1
            } catch {
                log.error("Could not schedule \(identifier): \(error.localizedDescription)")
            }
        }

        log.info("Dose reminders: \(desired.count) wanted, \(added) added, \(stale.count) removed")
    }

    // MARK: - Refill reminders

    /// One local, non-repeating notification per tracked medication, firing
    /// on the day it is expected to cross its refill threshold. Diffed and
    /// removed the same way dose reminders are, under its own identifier
    /// prefix so the two never collide.
    func applyRefills(_ specs: [RefillReminderSpec]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(RefillReminderSpec.identifierPrefix) }

        guard await NotificationService.shared.isAuthorized() else {
            if !pending.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: pending)
            }
            return
        }

        let desired = Dictionary(specs.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let existing = Set(pending)

        let stale = existing.subtracting(desired.keys)
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }

        var added = 0
        for (identifier, spec) in desired where !existing.contains(identifier) {
            let content = UNMutableNotificationContent()
            content.title = "Refill soon"
            content.body = spec.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: spec.dateComponents, repeats: false)
            )

            do {
                try await center.add(request)
                added += 1
            } catch {
                log.error("Could not schedule \(identifier): \(error.localizedDescription)")
            }
        }

        log.info("Refill reminders: \(desired.count) wanted, \(added) added, \(stale.count) removed")
    }

    /// One local, non-repeating notification per upcoming appointment, fired
    /// the evening before. Same diff, same permission rule, its own identifier
    /// prefix.
    func applyAppointments(_ specs: [AppointmentReminderSpec]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(AppointmentReminderSpec.identifierPrefix) }

        guard await NotificationService.shared.isAuthorized() else {
            if !pending.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: pending)
            }
            return
        }

        let desired = Dictionary(specs.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let existing = Set(pending)

        let stale = existing.subtracting(desired.keys)
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }

        var added = 0
        for (identifier, spec) in desired where !existing.contains(identifier) {
            let content = UNMutableNotificationContent()
            content.title = "Appointment tomorrow"
            content.body = spec.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: spec.dateComponents, repeats: false)
            )

            do {
                try await center.add(request)
                added += 1
            } catch {
                log.error("Could not schedule \(identifier): \(error.localizedDescription)")
            }
        }

        log.info("Appointment reminders: \(desired.count) wanted, \(added) added, \(stale.count) removed")
    }
}

// MARK: - Refill spec

/// One medication whose supply is about to cross its refill threshold. Not a
/// repeating reminder like `ReminderSpec`: it fires once, on the calculated
/// day, and the next foreground refresh recomputes it from whatever is left
/// on hand.
struct RefillReminderSpec: Hashable, Sendable, Identifiable {
    static let identifierPrefix = "refill-"

    let medicationID: UUID
    let personName: String
    let medicationName: String
    let dateComponents: DateComponents

    var id: String { identifier }

    var identifier: String {
        "\(Self.identifierPrefix)\(medicationID.uuidString)"
    }

    /// States a fact and stops, same as a dose reminder's body. Never says
    /// what happens if the medication is not refilled in time (1.4.1).
    var body: String {
        personName.isEmpty ? medicationName : "\(personName): \(medicationName)"
    }
}

/// Turns tracked medications into refill reminder specs. Pure, main-actor
/// only because SwiftData models are.
enum RefillReminderPlanner {

    /// A sane daytime hour for a reminder that is not tied to a dose time.
    static let notificationHour = 9

    /// Every refill reminder that should exist for `people`, one per
    /// medication that is tracked, scheduled, and due to cross its
    /// threshold. Medications with no `daysRemaining` (untracked or
    /// as-needed) get nothing.
    @MainActor
    static func requests(
        for people: [Person],
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> [RefillReminderSpec] {
        var specs: [RefillReminderSpec] = []

        for person in people where person.deletedAt == nil {
            for medication in person.liveMedications where isEligible(medication) {
                guard let daysRemaining = medication.daysRemaining else { continue }
                let daysUntilThreshold = daysRemaining - Double(medication.refillThresholdDays)
                let dayOffset = max(0, Int(daysUntilThreshold.rounded(.down)))

                guard
                    let fireDay = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: date)),
                    let fireDate = calendar.date(bySettingHour: notificationHour, minute: 0, second: 0, of: fireDay)
                else { continue }

                specs.append(
                    RefillReminderSpec(
                        medicationID: medication.id,
                        personName: person.displayLabel,
                        medicationName: medication.displayName,
                        dateComponents: calendar.dateComponents(
                            [.year, .month, .day, .hour, .minute], from: fireDate
                        )
                    )
                )
            }
        }

        return specs
    }

    private static func isEligible(_ medication: Medication) -> Bool {
        medication.deletedAt == nil && medication.isActive
    }
}

// MARK: - Appointment spec

/// One upcoming appointment worth a reminder the evening before.
///
/// The evening before, not two hours before: a 9am appointment reminded at 7am
/// is a reminder that arrives after the useful decisions (who is driving, is
/// the list printed) have already been missed. Non-repeating, like a refill
/// reminder, and recomputed on every foreground.
struct AppointmentReminderSpec: Hashable, Sendable, Identifiable {
    static let identifierPrefix = "appointment-"

    let visitID: UUID
    let personName: String
    let what: String
    let timeLabel: String
    let dateComponents: DateComponents

    var id: String { identifier }

    var identifier: String {
        "\(Self.identifierPrefix)\(visitID.uuidString)"
    }

    /// "Mom: cardiology tomorrow at 9:30 AM". States the fact and stops: it
    /// never says what happens if the appointment is missed (1.4.1).
    var body: String {
        let event = timeLabel.isEmpty
            ? "\(what) tomorrow"
            : "\(what) tomorrow at \(timeLabel)"
        return personName.isEmpty ? event : "\(personName): \(event)"
    }
}

/// Turns upcoming appointments into reminder specs. Pure, main-actor only
/// because SwiftData models are.
enum AppointmentReminderPlanner {

    /// 6pm the evening before: late enough to be after the working day, early
    /// enough to still do something about it.
    static let notificationHour = 18

    /// Every appointment reminder that should exist for `people`. An
    /// appointment already in the past gets nothing, and neither does one whose
    /// reminder time has itself already gone by: iOS drops a calendar trigger
    /// dated in the past, and re-adding it on every foreground would churn the
    /// diff forever.
    @MainActor
    static func requests(
        for people: [Person],
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> [AppointmentReminderSpec] {
        // Kept with the appointment's own date so the soonest survive the cap,
        // the way dose specs are ordered by next fire time. Sorting by
        // identifier alone would have let a UUID decide which of a family's
        // appointments got a reminder.
        var dated: [(Date, AppointmentReminderSpec)] = []

        for person in people where person.deletedAt == nil {
            for visit in person.upcomingVisits(asOf: date) {
                guard
                    let dayBefore = calendar.date(byAdding: .day, value: -1, to: visit.date),
                    let fireDate = calendar.date(
                        bySettingHour: notificationHour, minute: 0, second: 0, of: dayBefore
                    ),
                    fireDate > date
                else { continue }

                dated.append((
                    visit.date,
                    AppointmentReminderSpec(
                        visitID: visit.id,
                        personName: person.displayLabel,
                        what: what(visit),
                        timeLabel: visit.timeLabel(calendar: calendar),
                        dateComponents: calendar.dateComponents(
                            [.year, .month, .day, .hour, .minute], from: fireDate
                        )
                    )
                ))
            }
        }

        // Ties break on the identifier so the same input always yields the same
        // list and the diff settles instead of churning on every foreground.
        return dated
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.identifier < $1.1.identifier }
            .map(\.1)
    }

    /// Whatever the family actually typed, in the order that identifies the
    /// appointment on a lock screen.
    private static func what(_ visit: Visit) -> String {
        let candidates = [visit.resolvedProviderName, visit.specialty, visit.reason]
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return candidates.first { !$0.isEmpty } ?? "an appointment"
    }
}
