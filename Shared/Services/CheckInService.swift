import Foundation
import OSLog
import SwiftData
import UserNotifications

/// The proof-of-life button, and the one reminder that has to be reliable.
///
/// Two invariants live here and neither is a UI convention:
///
/// * **I2.** The press path contains no billing check at all. Not a hidden one,
///   not a disabled paywall: this file does not import `StoreService` and must
///   not start. The parent was told to press that button.
/// * **I6.** Nothing here detects anything or summons anyone. A press is a row.
///   An absent press is, eventually, a sentence on someone's lock screen.
///
/// The press writes locally first and syncs afterwards, so it works in a
/// basement with no signal, and `pressedAt` is the moment of the press rather
/// than the moment it reached the server.
@MainActor
@Observable
final class CheckInService {
    static let shared = CheckInService()

    private(set) var isPressing = false

    private let log = Logger(subsystem: "com.jackwallner.aging", category: "checkin")
    private var context: ModelContext { CareModelStore.sharedModelContainer.mainContext }

    /// Local notification identifier for the subject's own daily reminder. One
    /// per app, replaced on every settings change.
    private static let reminderID = "aging.checkin.reminder"

    private init() {}

    // MARK: Reading

    func settings(for person: Person) -> CheckInSettings? {
        let id = person.id
        var descriptor = FetchDescriptor<CheckInSettings>(predicate: #Predicate { $0.personID == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func lastCheckIn(for person: Person) -> CheckInRecord? {
        let id = person.id
        var descriptor = FetchDescriptor<CheckInRecord>(
            predicate: #Predicate { $0.personID == id },
            sortBy: [SortDescriptor(\.pressedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func hasCheckedInToday(_ person: Person, now: Date = Date()) -> Bool {
        guard let last = lastCheckIn(for: person) else { return false }
        return Calendar.current.isDate(last.pressedAt, inSameDayAs: now)
    }

    // MARK: Pressing

    /// `source` is what makes the sandwich case fall out with no special-casing:
    /// authorization keys off `linkedUserID`, never off role (D15). The same
    /// account presses their own button as a subject in one group and presses
    /// Dad's on his behalf as a caregiver in another.
    @discardableResult
    func press(
        for person: Person,
        source: CheckInSource,
        by name: String,
        at date: Date = Date()
    ) -> CheckInRecord {
        isPressing = true
        defer { isPressing = false }

        let record = CheckInRecord(
            id: UUID(),
            groupID: person.groupID,
            personID: person.id,
            source: source,
            pressedByName: name,
            pressedAt: date
        )
        context.insert(record)
        try? context.save()

        SyncCoordinator.shared.enqueue(.checkIn, id: record.id)
        Task { await SyncCoordinator.shared.syncNow() }
        return record
    }

    // MARK: Settings

    func upsertSettings(
        for person: Person,
        enabled: Bool,
        startMinute: Int,
        endMinute: Int,
        graceMinutes: Int
    ) {
        let settings = self.settings(for: person) ?? {
            let new = CheckInSettings(personID: person.id, groupID: person.groupID)
            context.insert(new)
            return new
        }()

        settings.groupID = person.groupID
        settings.enabled = enabled
        settings.windowStartMinute = startMinute
        settings.windowEndMinute = endMinute
        settings.graceMinutes = graceMinutes
        settings.timeZoneIdentifier = TimeZone.current.identifier
        settings.updatedAt = Date()
        settings.isDirty = true
        try? context.save()

        SyncCoordinator.shared.enqueue(.checkInSettings, id: person.id)
        Task {
            await SyncCoordinator.shared.syncNow()
            await scheduleReminder(for: person)
        }
    }

    // MARK: The local reminder (D26)

    /// A `UNCalendarNotificationTrigger`, not a server push and not a background
    /// task. This is the one thing on the parent's device that must fire on the
    /// dot every day, and a repeating calendar trigger is the only mechanism iOS
    /// actually guarantees. It survives being offline, being in a drawer, and
    /// Low Power Mode.
    func scheduleReminder(for person: Person) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.reminderID])

        guard let settings = settings(for: person), settings.enabled else { return }
        guard await NotificationService.shared.isAuthorized() else { return }

        // Halfway through the window: early enough that a late press still
        // lands inside it, late enough not to wake anyone.
        let minute = (settings.windowStartMinute + settings.windowEndMinute) / 2

        var components = DateComponents()
        components.hour = minute / 60
        components.minute = minute % 60

        let content = UNMutableNotificationContent()
        content.title = "Let them know you're OK"
        content.body = "Tap to check in for today."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.reminderID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )

        do {
            try await center.add(request)
            log.info("Daily check-in reminder scheduled for \(components.hour ?? 0):\(components.minute ?? 0)")
        } catch {
            log.error("Could not schedule the reminder: \(error.localizedDescription)")
        }
    }

    static func windowLabel(start: Int, end: Int) -> String {
        "\(ScheduleEngine.timeLabel(forMinutes: start)) to \(ScheduleEngine.timeLabel(forMinutes: end))"
    }
}
