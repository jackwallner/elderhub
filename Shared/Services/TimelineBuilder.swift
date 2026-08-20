import Foundation

// MARK: - Timeline entry

enum TimelineEntryKind: String, CaseIterable, Identifiable, Sendable {
    case visit
    case vital
    case careEvent
    case taskCompleted
    case checkIn
    case medicationStarted
    case medicationStopped
    case doseIssue

    var id: String { rawValue }

    var label: String {
        switch self {
        case .visit: return "Visit"
        case .vital: return "Vital"
        case .careEvent: return "Incident"
        case .taskCompleted: return "Task done"
        case .checkIn: return "Check-in"
        case .medicationStarted: return "Medication started"
        case .medicationStopped: return "Medication stopped"
        case .doseIssue: return "Dose"
        }
    }

    var symbol: String {
        switch self {
        case .visit: return "stethoscope"
        case .vital: return "chart.xyaxis.line"
        case .careEvent: return "note.text"
        case .taskCompleted: return "checkmark.circle"
        case .checkIn: return "hand.wave"
        case .medicationStarted: return "plus.circle"
        case .medicationStopped: return "minus.circle"
        case .doseIssue: return "exclamationmark.circle"
        }
    }
}

/// One row in a person's merged history (plan82 slice E). Every field comes
/// from data already sitting in the local SwiftData store (I1); nothing here
/// is fetched or computed over the network.
struct TimelineEntry: Identifiable, Hashable, Sendable {
    let date: Date
    let kind: TimelineEntryKind
    let title: String
    let detail: String
    let personID: UUID
    let recordedBy: String

    /// Derived rather than stored: nothing in the source rows needs a new
    /// identity, and `kind` plus `date` plus `title` is already unique across
    /// everything this builder produces (started/stopped share a medication's
    /// dates but never its kind).
    var id: String {
        "\(personID.uuidString)|\(kind.rawValue)|\(date.timeIntervalSince1970)|\(title)"
    }
}

// MARK: - Builder

/// Merges a person's history into one list, sorted newest first. Pure: every
/// input is an already-fetched array, so this is testable without a
/// `ModelContext`, the same way `ScheduleEngine` is. No SwiftData import, no
/// fetching: callers own the querying and the windowing.
enum TimelineBuilder {

    @MainActor
    static func build(
        personID: UUID,
        visits: [Visit] = [],
        vitals: [VitalReading] = [],
        careEvents: [CareEvent] = [],
        tasks: [CareTask] = [],
        checkIns: [CheckInRecord] = [],
        medications: [Medication] = [],
        doseLogs: [DoseLog] = [],
        now: Date = Date()
    ) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []

        // History only. A visit dated ahead is an appointment nobody has been
        // to yet (`Visit.isUpcoming`), and putting it at the top of a
        // reverse-chronological history says it happened.
        entries += visits
            .filter { $0.deletedAt == nil && !$0.isUpcoming(asOf: now) }
            .map { visit in
                TimelineEntry(
                    date: visit.date,
                    kind: .visit,
                    title: visitTitle(visit),
                    detail: visit.reason,
                    personID: personID,
                    recordedBy: ""
                )
            }

        entries += vitals
            .filter { $0.deletedAt == nil }
            .map { reading in
                TimelineEntry(
                    date: reading.recordedAt,
                    kind: .vital,
                    title: "\(reading.kind.label): \(reading.displayValue) \(reading.kind.unit)",
                    detail: reading.note,
                    personID: personID,
                    recordedBy: ""
                )
            }

        entries += careEvents
            .filter { $0.deletedAt == nil }
            .map { event in
                TimelineEntry(
                    date: event.occurredAt,
                    kind: .careEvent,
                    title: event.kind.label,
                    detail: event.note,
                    personID: personID,
                    recordedBy: event.recordedBy
                )
            }

        // Only tasks actually ticked off. An open task belongs on the task
        // list, not in a history of what happened.
        entries += tasks
            .filter { $0.deletedAt == nil }
            .compactMap { task -> TimelineEntry? in
                guard let completedAt = task.completedAt else { return nil }
                return TimelineEntry(
                    date: completedAt,
                    kind: .taskCompleted,
                    title: task.title,
                    detail: task.notes,
                    personID: personID,
                    recordedBy: task.completedByName
                )
            }

        entries += checkIns.map { record in
            TimelineEntry(
                date: record.pressedAt,
                kind: .checkIn,
                title: "Checked in",
                detail: record.note,
                personID: personID,
                recordedBy: record.pressedByName
            )
        }

        for medication in medications where medication.deletedAt == nil {
            entries.append(
                TimelineEntry(
                    date: medication.startDate,
                    kind: .medicationStarted,
                    title: "\(medication.displayName) started",
                    detail: medication.purpose,
                    personID: personID,
                    recordedBy: ""
                )
            )
            if let endDate = medication.endDate {
                entries.append(
                    TimelineEntry(
                        date: endDate,
                        kind: .medicationStopped,
                        title: "\(medication.displayName) stopped",
                        detail: medication.purpose,
                        personID: personID,
                        recordedBy: ""
                    )
                )
            }
        }

        // Taken doses are the overwhelming majority of rows and would bury
        // everything else; missed and skipped are the signal.
        entries += doseLogs
            .filter { $0.deletedAt == nil && $0.status != .taken }
            .map { log -> TimelineEntry in
                let medicationName: String = log.medication?.displayName ?? "Medication"
                let statusLabel: String = log.status.label.lowercased()
                let title: String = "\(medicationName) \(statusLabel)"
                return TimelineEntry(
                    date: log.scheduledAt,
                    kind: .doseIssue,
                    title: title,
                    detail: log.note,
                    personID: personID,
                    recordedBy: log.recordedBy
                )
            }

        return entries.sorted { $0.date > $1.date }
    }

    private static func visitTitle(_ visit: Visit) -> String {
        let name = visit.resolvedProviderName
        return name.isEmpty ? "Visit" : "Visit: \(name)"
    }
}
