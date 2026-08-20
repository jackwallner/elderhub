import Foundation
import OSLog
import SwiftData
import UserNotifications

// MARK: - Spec

/// One local notification we want iOS to be holding: everything a person has
/// due at a single time of day, on a single weekday (or every day).
///
/// One request per *dose time*, not per medication. Per medication is what this
/// was, and it is what put a three-parent family past the device's 64 pending
/// requests: the count grew with medications x times x weekdays, so the
/// furthest-out reminders were silently never scheduled. Grouping makes it grow
/// with people x distinct dose times instead, which no realistic family gets
/// near. It is also the better notification: five buzzes at 8am, one per
/// tablet, is worse than one that says how many are due.
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

    /// Carried so a tap can open the right person. Two parents produce two
    /// lock-screen reminders a minute apart, and before this the app opened
    /// wherever it was left, which with a circle of two is the wrong record
    /// about half the time.
    let personID: UUID
    let personName: String
    /// Every medication due at this time, sorted, so identical input always
    /// produces an identical request.
    let medicationNames: [String]
    let hour: Int
    let minute: Int
    /// `Calendar`'s 1-indexed, Sunday-first weekday. Nil means every day.
    let weekday: Int?

    var id: String { identifier }

    /// `dose-<personID>-<minutes>-<weekday>`, with `0` (not a valid `Calendar`
    /// weekday) standing in for every day. Derived entirely from the schedule,
    /// so rescheduling identical input produces identical identifiers and the
    /// diff is a no-op.
    ///
    /// Deliberately *not* keyed on the medications in the group: adding a
    /// tablet to an 8am slot has to update the reminder already sitting there
    /// rather than add a second one. That is why the scheduler diffs on the
    /// body as well as the identifier.
    var identifier: String {
        "\(Self.identifierPrefix)\(personID.uuidString)-\(hour * 60 + minute)-\(weekday ?? 0)"
    }

    /// Says how many, so the count on the lock screen matches what the app will
    /// show when it opens. Never says anything about the consequence of
    /// missing them (1.4.1).
    var title: String {
        medicationNames.count > 1 ? "Time for \(medicationNames.count) doses" : "Time for a dose"
    }

    /// Deliberately says whose dose it is. Every other med reminder on the App
    /// Store is single-user; "Mom: Metformin 500 mg" is the whole difference on
    /// a lock screen holding reminders for two parents.
    ///
    /// Two names in full, then a count. A body that lists six medications is
    /// truncated by the system anyway, and truncation would cut it mid-drug.
    ///
    /// States a fact and stops. It never says what happens if the dose is
    /// missed, which would be a claim about a medical outcome (1.4.1).
    var body: String {
        let listed: String
        switch medicationNames.count {
        case 0:
            listed = "a dose is due"
        case 1:
            listed = medicationNames[0]
        case 2:
            listed = "\(medicationNames[0]) and \(medicationNames[1])"
        default:
            listed = "\(medicationNames[0]), \(medicationNames[1]) and \(medicationNames.count - 2) more"
        }
        return personName.isEmpty ? listed : "\(personName): \(listed)"
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

    /// What the planner wanted, and what fits.
    ///
    /// `droppedCount` exists so the overflow can be *said out loud*. The cap
    /// itself is unavoidable (the device limit is not ours), but a caregiver
    /// whose evening reminders quietly stopped being scheduled has no way to
    /// find that out, and a reminder you believe in that does not arrive is
    /// worse than no reminder at all.
    struct Plan: Sendable {
        var scheduled: [ReminderSpec]
        var droppedCount: Int
    }

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
        plan(for: people, on: date, calendar: calendar).scheduled
    }

    /// The grouped, capped plan, plus how much of it did not fit.
    @MainActor
    static func plan(
        for people: [Person],
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> Plan {
        // (person, time, weekday) -> the medications due then. A medication with
        // no weekdays is every day and lands under `nil`; one restricted to
        // Monday lands under Monday. The two are separate requests on purpose:
        // merging them would mean expanding every daily medication across all
        // seven weekdays, which costs seven requests to save one.
        var grouped: [GroupKey: [String]] = [:]
        var personNames: [UUID: String] = [:]

        for person in people where person.deletedAt == nil {
            personNames[person.id] = person.displayLabel

            for medication in person.liveMedications where isEligible(medication, on: date, calendar: calendar) {
                let name = medication.displayName

                for minutes in medication.scheduleMinutes.sorted() {
                    let weekdays: [Int?] = medication.weekdays.isEmpty
                        ? [nil]
                        : medication.weekdays.sorted().map { $0 }

                    for weekday in weekdays {
                        let key = GroupKey(
                            personID: person.id,
                            hour: minutes / 60,
                            minute: minutes % 60,
                            weekday: weekday
                        )
                        grouped[key, default: []].append(name)
                    }
                }
            }
        }

        let specs = grouped.map { key, names in
            ReminderSpec(
                personID: key.personID,
                personName: personNames[key.personID] ?? "",
                // Sorted and de-duplicated: two rows of the same drug at the
                // same time is a data entry slip, not two tablets to announce.
                medicationNames: Array(Set(names)).sorted(),
                hour: key.hour,
                minute: key.minute,
                weekday: key.weekday
            )
        }

        let kept = cap(specs, on: date, calendar: calendar)
        return Plan(scheduled: kept, droppedCount: specs.count - kept.count)
    }

    private struct GroupKey: Hashable {
        let personID: UUID
        let hour: Int
        let minute: Int
        let weekday: Int?
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

    /// Everything this phone wants iOS to be holding, and how much of it did
    /// not fit.
    ///
    /// One type built in one place, because `refresh` and the screen that tells
    /// the user about the overflow have to agree: a warning computed a second
    /// way is a warning that can be wrong.
    struct DevicePlan: Sendable {
        var doses: [ReminderSpec] = []
        var refills: [RefillReminderSpec] = []
        var appointments: [AppointmentReminderSpec] = []
        /// Reminders the device budget had no room for, across all three kinds.
        var droppedCount: Int = 0
    }

    /// Reads the people out of SwiftData on the main actor and works out what
    /// should be pending. Pure apart from the fetch, so a screen can call it
    /// just to ask whether anything is being dropped.
    @MainActor
    static func plan(in context: ModelContext, now: Date = Date()) -> DevicePlan {
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        let enabled = people.filter { DoseReminderPreferences.isEnabled(personID: $0.id) }

        let doses = DoseReminderPlanner.plan(for: enabled, on: now)

        // Refill reminders share this actor's notification center and the
        // same 64-request device budget, so they only get whatever dose
        // reminders left behind.
        let refillSpecs = RefillReminderPlanner.requests(for: enabled, on: now)
        let refillBudget = max(0, DoseReminderPlanner.limit - doses.scheduled.count)
        let refills = Array(refillSpecs.prefix(refillBudget))

        // Appointments come last out of the same budget. They are the rarest of
        // the three and the ones a caregiver is least likely to have twenty of,
        // so taking whatever is left over costs nothing in practice.
        let appointmentSpecs = AppointmentReminderPlanner.requests(for: enabled, on: now)
        let appointmentBudget = max(0, DoseReminderPlanner.limit - doses.scheduled.count - refills.count)
        let appointments = Array(appointmentSpecs.prefix(appointmentBudget))

        return DevicePlan(
            doses: doses.scheduled,
            refills: refills,
            appointments: appointments,
            droppedCount: doses.droppedCount
                + (refillSpecs.count - refills.count)
                + (appointmentSpecs.count - appointments.count)
        )
    }

    /// The entry point every caller uses: plan on the main actor, hand the
    /// resulting value types off it.
    @MainActor
    static func refresh(in context: ModelContext, now: Date = Date()) async {
        let plan = plan(in: context, now: now)
        await shared.apply(plan.doses)
        await shared.applyRefills(plan.refills)
        await shared.applyAppointments(plan.appointments)
    }

    func apply(_ specs: [ReminderSpec]) async {
        let center = UNUserNotificationCenter.current()
        // Bodies as well as identifiers: one request now covers every
        // medication due at that time, so adding a tablet to the 8am slot has
        // to rewrite the request already sitting there. Comparing identifiers
        // alone would leave yesterday's wording pending forever.
        let ours = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(ReminderSpec.identifierPrefix) }
        let pending = ours.map(\.identifier)

        // Permission can be revoked in Settings long after the toggles were set.
        // Clear ours out rather than leaving stale requests behind.
        guard await NotificationService.shared.isAuthorized() else {
            if !pending.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: pending)
            }
            return
        }

        let desired = Dictionary(specs.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let existingBodies = Dictionary(
            ours.map { ($0.identifier, $0.content.body) },
            uniquingKeysWith: { first, _ in first }
        )
        let existing = Set(pending)

        let stale = existing.subtracting(desired.keys)
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }

        var added = 0
        // Adding under an existing identifier replaces it, so a changed body
        // needs no removal first.
        for (identifier, spec) in desired where existingBodies[identifier] != spec.body {
            let content = UNMutableNotificationContent()
            content.title = spec.title
            content.body = spec.body
            content.sound = .default
            content.userInfo = [NotificationRoute.personKey: spec.personID.uuidString]

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
            content.userInfo = [NotificationRoute.personKey: spec.personID.uuidString]
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
            content.userInfo = [NotificationRoute.personKey: spec.personID.uuidString]
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
    let personID: UUID
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
                        personID: person.id,
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
    let personID: UUID
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
                        personID: person.id,
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
