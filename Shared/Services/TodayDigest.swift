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
    /// Whether a daily check-in has been agreed for this person, and whether
    /// today's has happened. Not derivable from the models: the settings and
    /// the presses live in `CheckInService`, so they are handed in.
    let hasCheckIn: Bool
    let checkedInToday: Bool

    var id: UUID { person.id }

    /// A check-in that has been agreed and has not happened yet today. The one
    /// outstanding thing on this screen that nobody in the family can tick off:
    /// it is a statement about a button that has not been pressed, never an
    /// assessment of the person who did not press it (I6).
    var checkInOutstanding: Bool { hasCheckIn && !checkedInToday }

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
            && runningLow.isEmpty && billsDue.isEmpty && !checkInOutstanding
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
        hasCheckIn: Bool = false,
        checkedInToday: Bool = false,
        now: Date
    ) {
        self.person = person
        self.slots = slots
        self.tasksDue = tasksDue
        self.appointments = appointments
        self.runningLow = runningLow
        self.billsDue = billsDue
        self.hasCheckIn = hasCheckIn
        self.checkedInToday = checkedInToday
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
        // Last, because it is the one line here nobody can act on, and named
        // rather than counted. Before this a person whose only outstanding
        // thing was an unpressed check-in was filed under "Nothing due today",
        // which is the opposite of the answer the sibling opening the app came
        // for.
        if checkInOutstanding {
            parts.append("no check-in yet")
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
    /// `checkInState` is handed in rather than read here so this file stays
    /// pure functions over the models, like `ScheduleEngine` and `TaskPlanner`.
    /// The default answers "no check-in agreed", which is what every caller
    /// outside Today wants: the Care row is an inventory of the record, and the
    /// button lives on the daily screen.
    static func build(
        for people: [Person],
        on date: Date = Date(),
        calendar: Calendar = .current,
        checkInState: (Person) -> (enabled: Bool, checkedIn: Bool) = { _ in (false, false) }
    ) -> [PersonDigest] {
        people
            .filter { $0.deletedAt == nil }
            .map { person in
                let checkIn = checkInState(person)
                return PersonDigest(
                    person: person,
                    slots: ScheduleEngine.slots(for: person, on: date, calendar: calendar),
                    tasksDue: TaskPlanner.dueNow(person.liveTasks, now: date, calendar: calendar),
                    appointments: person.appointmentsDue(now: date, calendar: calendar),
                    runningLow: runningLow(for: person),
                    billsDue: BillPlanner.needingAttention(person.liveBills, now: date, calendar: calendar),
                    hasCheckIn: checkIn.enabled,
                    checkedInToday: checkIn.checkedIn,
                    now: date
                )
            }
    }

    /// The line above the whole list in Everyone mode.
    ///
    /// Leads with overdue when there is any, because that is the only number on
    /// the screen that means "this should already have happened".
    ///
    /// It has to agree with `isClear`, which is what decides whether a person
    /// is listed as outstanding below it. This counted doses and tasks only,
    /// while `isClear` also counts appointments, refills and bills, so a family
    /// whose only outstanding thing was a bill got the headline "Nothing due
    /// today" printed directly above a section listing that bill. A screen
    /// contradicting itself in two adjacent lines is worse than either line
    /// alone, and refills and bills are common enough that this was not an
    /// exotic case. They are summarised rather than enumerated, matching how
    /// the rows below treat them: errands for later in the week, not doses.
    @MainActor
    static func headline(for digests: [PersonDigest]) -> String {
        let overdue = digests.reduce(0) { $0 + $1.overdueSlots.count }
        let due = digests.reduce(0) { $0 + $1.upcomingSlots.count }
        let tasks = digests.reduce(0) { $0 + $1.tasksDue.count }
        let appointments = digests.reduce(0) { $0 + $1.appointments.count }
        let errands = digests.reduce(0) { $0 + $1.runningLow.count + $1.billsDue.count }
        let awaitingCheckIn = digests.filter(\.checkInOutstanding).count

        var parts: [String] = []
        if overdue > 0 { parts.append(overdue == 1 ? "1 dose overdue" : "\(overdue) doses overdue") }
        if due > 0 { parts.append(due == 1 ? "1 dose due" : "\(due) doses due") }
        if tasks > 0 { parts.append(tasks == 1 ? "1 task" : "\(tasks) tasks") }
        if appointments > 0 {
            parts.append(appointments == 1 ? "1 appointment" : "\(appointments) appointments")
        }
        if errands > 0 { parts.append(errands == 1 ? "1 to sort out" : "\(errands) to sort out") }
        if awaitingCheckIn > 0 {
            parts.append(
                awaitingCheckIn == 1 ? "1 check-in outstanding" : "\(awaitingCheckIn) check-ins outstanding"
            )
        }

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
