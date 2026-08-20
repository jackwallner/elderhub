import Foundation

/// One scheduled dose on a given day, resolved against whatever has already been logged.
struct DoseSlot: Identifiable, Hashable {
    let id: String
    let medicationID: UUID
    let medicationName: String
    let strength: String
    let scheduledAt: Date
    let status: DoseStatus?
    let recordedBy: String

    var isPending: Bool { status == nil }
}

/// Builds the day's dose list for a person. Pure functions over the model objects so
/// the logic stays testable without a container.
enum ScheduleEngine {

    /// Every scheduled dose for `person` on `date`, in time order, matched against
    /// existing `DoseLog` entries.
    @MainActor
    static func slots(for person: Person, on date: Date, calendar: Calendar = .current) -> [DoseSlot] {
        var result: [DoseSlot] = []

        for medication in person.activeMedications {
            for time in medication.doseTimes(on: date, calendar: calendar) {
                let log = medication.liveDoses.first { calendar.isDate($0.scheduledAt, equalTo: time, toGranularity: .minute) }
                result.append(
                    DoseSlot(
                        id: "\(medication.id.uuidString)-\(time.timeIntervalSince1970)",
                        medicationID: medication.id,
                        medicationName: medication.name,
                        strength: medication.strength,
                        scheduledAt: time,
                        status: log?.status,
                        recordedBy: log?.recordedBy ?? ""
                    )
                )
            }
        }

        return result.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    /// Doses still pending whose time has passed. Drives the "needs attention" count.
    @MainActor
    static func overdueSlots(
        for person: Person,
        on date: Date = Date(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DoseSlot] {
        slots(for: person, on: date, calendar: calendar)
            .filter { $0.isPending && $0.scheduledAt < now }
    }

    /// Share of scheduled doses marked taken over a window ending today.
    @MainActor
    static func adherence(
        for person: Person,
        days: Int,
        endingOn date: Date = Date(),
        calendar: Calendar = .current
    ) -> Double? {
        guard days > 0 else { return nil }
        var scheduled = 0
        var taken = 0

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            for slot in slots(for: person, on: day, calendar: calendar) {
                scheduled += 1
                if slot.status == .taken { taken += 1 }
            }
        }

        guard scheduled > 0 else { return nil }
        return Double(taken) / Double(scheduled)
    }

    /// Formats minutes-from-midnight for display and for the schedule editor.
    static func timeLabel(forMinutes minutes: Int, calendar: Calendar = .current) -> String {
        let startOfDay = calendar.startOfDay(for: Date())
        guard let date = calendar.date(byAdding: .minute, value: minutes, to: startOfDay) else {
            return ""
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// How a `Medication.weekdays` list reads on a printed list: "" for every
    /// day, "Mondays" for a single day, "Mon, Wed, Fri" otherwise.
    ///
    /// Empty is the model's "every day", and every day needs no words: a line
    /// saying "Sun, Mon, Tue, Wed, Thu, Fri, Sat" beside four dose times is
    /// noise on the one page somebody reads in a hurry. Seven days selected
    /// means the same thing and reads the same way.
    static func weekdayLabel(for weekdays: [Int], calendar: Calendar = .current) -> String {
        let days = Set(weekdays.filter { (1...7).contains($0) })
        guard !days.isEmpty, days.count < 7 else { return "" }

        let ordered = orderedWeekdays(calendar: calendar).filter { days.contains($0) }
        if ordered.count == 1, let only = ordered.first {
            // "Mondays", not "Mon": a weekly tablet is the case this exists
            // for, and the plural is what a person says out loud.
            let symbols = calendar.weekdaySymbols
            let name = symbols.indices.contains(only - 1) ? symbols[only - 1] : ""
            return name.isEmpty ? "" : "\(name)s"
        }

        let short = calendar.shortWeekdaySymbols
        return ordered
            .compactMap { short.indices.contains($0 - 1) ? short[$0 - 1] : nil }
            .joined(separator: ", ")
    }

    /// 1...7 starting at the calendar's own first weekday, so a Monday-first
    /// locale never reads its own week back to front.
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        let first = calendar.firstWeekday
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
