import Foundation

/// What is outstanding for one person right now, and the one-line version of it.
///
/// This exists because the app was sold on "everyone you look after, in one
/// circle" while the Today tab could only ever answer for one of them. A
/// caregiver looking at Mom had no way to know Dad's 8am dose was still
/// unticked, and the Care tab, the only screen showing both people at once,
/// said "Dad · 4 medications", which is an inventory count and not a status.
///
/// Pure functions over the model objects, like `ScheduleEngine` and
/// `TaskPlanner`, so the counting is testable without a view or a container.
/// Both screens read this one type, so "2 due" on the person row and the rows
/// under that person's heading on Today cannot drift apart.
struct PersonDigest: Identifiable {
    let person: Person
    /// Every scheduled slot for today, ticked or not. The view needs the whole
    /// day so a caregiver can still undo one that was recorded by mistake.
    let slots: [DoseSlot]
    let tasksDue: [CareTask]
    let appointments: [Visit]
    let runningLow: [Medication]
    let billsDue: [Bill]

    var id: UUID { person.id }

    /// Scheduled, still unticked, and the time has passed. Deliberately not
    /// "not taken": a dose logged as skipped is an answered question.
    var overdueSlots: [DoseSlot] { slots.filter { $0.isPending && $0.scheduledAt < now } }

    /// Unticked and still ahead of us today.
    var upcomingSlots: [DoseSlot] { slots.filter { $0.isPending && $0.scheduledAt >= now } }

    var pendingSlots: [DoseSlot] { slots.filter(\.isPending) }

    /// True when there is genuinely nothing left for this person today. The
    /// Everyone view collapses these rather than printing a heading over an
    /// absence.
    var isClear: Bool {
        pendingSlots.isEmpty && tasksDue.isEmpty && appointments.isEmpty
            && runningLow.isEmpty && billsDue.isEmpty
    }

    /// True when there is nothing outstanding *and* nothing recorded either,
    /// which is a record with no medications rather than a day already done.
    var hasNothingToShow: Bool { isClear && slots.isEmpty }

    private let now: Date

    init(
        person: Person,
        slots: [DoseSlot],
        tasksDue: [CareTask],
        appointments: [Visit],
        runningLow: [Medication],
        billsDue: [Bill],
        now: Date
    ) {
        self.person = person
        self.slots = slots
        self.tasksDue = tasksDue
        self.appointments = appointments
        self.runningLow = runningLow
        self.billsDue = billsDue
        self.now = now
    }

    /// The person-row subtitle on the Care tab.
    ///
    /// A statement of what is recorded and what is outstanding, never an
    /// assessment of the person or of whoever is looking after them (I6).
    /// "Nothing due today" is a fact about a list. It is not praise, and
    /// "2 doses overdue" is not a reprimand.
    var statusLine: String {
        var parts: [String] = []
        let overdue = overdueSlots.count
        if overdue > 0 {
            parts.append(overdue == 1 ? "1 dose overdue" : "\(overdue) doses overdue")
        }
        let upcoming = upcomingSlots.count
        if upcoming > 0 {
            parts.append(overdue > 0 ? "\(upcoming) later" : (upcoming == 1 ? "1 dose due" : "\(upcoming) doses due"))
        }
        if !tasksDue.isEmpty {
            parts.append(tasksDue.count == 1 ? "1 task" : "\(tasksDue.count) tasks")
        }
        if !appointments.isEmpty {
            parts.append(appointments.count == 1 ? "1 appointment" : "\(appointments.count) appointments")
        }
        if !runningLow.isEmpty {
            parts.append("\(runningLow.count) running low")
        }
        if !billsDue.isEmpty {
            parts.append(billsDue.count == 1 ? "1 bill" : "\(billsDue.count) bills")
        }

        if parts.isEmpty {
            // Two different silences, and telling them apart is the whole point
            // of the row: a record with nothing in it yet must not read as a
            // day that has been dealt with.
            return person.activeMedications.isEmpty && slots.isEmpty
                ? "Nothing recorded yet"
                : "Nothing due today"
        }
        return parts.joined(separator: " · ")
    }
}

enum TodayDigest {

    @MainActor
    static func build(
        for people: [Person],
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> [PersonDigest] {
        people
            .filter { $0.deletedAt == nil }
            .map { person in
                PersonDigest(
                    person: person,
                    slots: ScheduleEngine.slots(for: person, on: date, calendar: calendar),
                    tasksDue: TaskPlanner.dueNow(person.liveTasks, now: date, calendar: calendar),
                    appointments: person.appointmentsDue(now: date, calendar: calendar),
                    runningLow: runningLow(for: person),
                    billsDue: BillPlanner.needingAttention(person.liveBills, now: date, calendar: calendar),
                    now: date
                )
            }
    }

    /// The line above the whole list in Everyone mode.
    ///
    /// Leads with overdue when there is any, because that is the only number on
    /// the screen that means "this should already have happened".
    @MainActor
    static func headline(for digests: [PersonDigest]) -> String {
        let overdue = digests.reduce(0) { $0 + $1.overdueSlots.count }
        let due = digests.reduce(0) { $0 + $1.upcomingSlots.count }
        let tasks = digests.reduce(0) { $0 + $1.tasksDue.count }

        var parts: [String] = []
        if overdue > 0 { parts.append(overdue == 1 ? "1 dose overdue" : "\(overdue) doses overdue") }
        if due > 0 { parts.append(due == 1 ? "1 dose due" : "\(due) doses due") }
        if tasks > 0 { parts.append(tasks == 1 ? "1 task" : "\(tasks) tasks") }

        guard !parts.isEmpty else { return "Nothing due today" }
        return parts.joined(separator: " · ")
    }

    /// The refill rule, in one place. `TodayView` had its own copy of this and
    /// the person row would have needed a second, which is two chances for
    /// "running low" to mean two different things on two screens.
    ///
    /// `daysRemaining` is nil for anything not tracking refills (migration
    /// 0016 split "not tracked" from "empty"), so an untracked bottle never
    /// appears here, and a tracked empty one reports 0 rather than nil.
    @MainActor
    static func runningLow(for person: Person) -> [Medication] {
        person.activeMedications
            .filter { medication in
                guard let daysRemaining = medication.daysRemaining else { return false }
                return daysRemaining <= Double(medication.refillThresholdDays)
            }
            .sorted { ($0.daysRemaining ?? 0) < ($1.daysRemaining ?? 0) }
    }
}
