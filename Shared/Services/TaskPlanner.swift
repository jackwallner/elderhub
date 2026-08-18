import Foundation

// MARK: - Buckets

/// Where an open task sits relative to now. Deliberately coarse: a caregiver
/// scanning the list wants "is this late, is this today, or is this later",
/// not a countdown.
enum CareTaskBucket: String, CaseIterable, Identifiable, Sendable {
    case overdue, today, tomorrow, thisWeek, later, someday

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This week"
        case .later: return "Later"
        case .someday: return "No date"
        }
    }

    /// Ascending, so a plain sort produces the order the list renders in.
    var sortWeight: Int {
        switch self {
        case .overdue: return 0
        case .today: return 1
        case .tomorrow: return 2
        case .thisWeek: return 3
        case .later: return 4
        case .someday: return 5
        }
    }
}

// MARK: - Planner

/// Pure functions over already-fetched `CareTask` rows, the same shape as
/// `ScheduleEngine`, `TimelineBuilder` and `CareSearch`: no `ModelContext`, no
/// fetching, no network. Callers own the querying; this only buckets, sorts and
/// does the calendar arithmetic, which is the part worth testing.
enum TaskPlanner {

    // MARK: Recurrence

    /// The next occurrence at or after `notBefore`, stepping by whole calendar
    /// units from `date`.
    ///
    /// Stepping repeatedly rather than adding one interval is what stops a
    /// monthly bill that went three months unticked from spawning a follow-up
    /// that is already overdue the moment it is created. The iteration cap is a
    /// guard against a pathological calendar, not an expected path.
    static func nextDueDate(
        after date: Date,
        recurrence: CareTaskRecurrence,
        notBefore: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard let step = recurrence.step else { return nil }

        var next = date
        var iterations = 0
        while iterations < 500 {
            guard let advanced = calendar.date(byAdding: step, to: next) else { return nil }
            next = advanced
            iterations += 1
            if next > notBefore { return next }
        }
        return next
    }

    // MARK: Assignment

    /// Whether `task` is this person's to do.
    ///
    /// The id is the answer whenever both sides have one: two siblings called
    /// Chris must not both own the same errand. The name is the fallback rather
    /// than the rule because `assigneeUserID` is only set when the assignee was
    /// picked from a loaded member list, and typing a name on a phone that has
    /// never been online is a supported way to assign someone (I1). A task with
    /// an id read on a device whose member list has not loaded yet falls back
    /// the same way, so "Mine" is never silently empty while offline.
    @MainActor
    static func isAssigned(_ task: CareTask, to userID: UUID?, named name: String) -> Bool {
        if let taskUserID = task.assigneeUserID, let userID {
            return taskUserID == userID
        }
        let mine = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mine.isEmpty else { return false }
        let theirs = task.assigneeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !theirs.isEmpty else { return false }
        return theirs.localizedCaseInsensitiveCompare(mine) == .orderedSame
    }

    /// Only the tasks assigned to this person. Order is preserved, so it can be
    /// dropped in front of `openSections` or behind `dueNow` without changing
    /// how either sorts.
    @MainActor
    static func assigned(_ tasks: [CareTask], to userID: UUID?, named name: String) -> [CareTask] {
        tasks.filter { isAssigned($0, to: userID, named: name) }
    }

    // MARK: Bucketing

    @MainActor
    static func bucket(
        for task: CareTask,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CareTaskBucket {
        guard let dueAt = task.dueAt else { return .someday }

        if calendar.isDate(dueAt, inSameDayAs: now) { return .today }
        // Checked after "today" so a due time earlier this morning still reads
        // as today's work rather than as something already missed.
        if dueAt < now { return .overdue }

        let startOfToday = calendar.startOfDay(for: now)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
           calendar.isDate(dueAt, inSameDayAs: tomorrow) {
            return .tomorrow
        }
        if let weekOut = calendar.date(byAdding: .day, value: 7, to: startOfToday), dueAt < weekOut {
            return .thisWeek
        }
        return .later
    }

    /// Open tasks grouped into their buckets, soonest bucket first, and within
    /// a bucket soonest-then-highest-priority first. Empty buckets are dropped
    /// so the list has no headers with nothing under them.
    @MainActor
    static func openSections(
        _ tasks: [CareTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [(bucket: CareTaskBucket, tasks: [CareTask])] {
        let open = tasks.filter { $0.deletedAt == nil && !$0.isDone }
        let grouped = Dictionary(grouping: open) { bucket(for: $0, now: now, calendar: calendar) }
        return grouped.keys
            .sorted { $0.sortWeight < $1.sortWeight }
            .map { key in (bucket: key, tasks: sorted(grouped[key] ?? [])) }
    }

    /// What the Today tab shows: everything already late plus everything due
    /// today. Tomorrow deliberately does not appear, because a list that shows
    /// work not yet due is a list people stop trusting as "what's left".
    @MainActor
    static func dueNow(
        _ tasks: [CareTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CareTask] {
        sorted(
            tasks.filter { task in
                guard task.deletedAt == nil, !task.isDone else { return false }
                let slot = bucket(for: task, now: now, calendar: calendar)
                return slot == .overdue || slot == .today
            }
        )
    }

    /// Recently ticked-off tasks, newest first, for the "Done" section. Bounded
    /// by a window rather than a count so the section stays a record of the
    /// last few weeks instead of growing into a second full list.
    @MainActor
    static func recentlyCompleted(
        _ tasks: [CareTask],
        now: Date = Date(),
        withinDays days: Int = 30,
        calendar: Calendar = .current
    ) -> [CareTask] {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: now) else { return [] }
        let done: [CareTask] = tasks.filter { task in
            guard task.deletedAt == nil, let completedAt = task.completedAt else { return false }
            return completedAt >= cutoff
        }
        return done.sorted { lhs, rhs in
            (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast)
        }
    }

    /// Soonest due first (undated last), then higher priority, then title, so
    /// the order is stable across launches rather than following fetch order.
    @MainActor
    private static func sorted(_ tasks: [CareTask]) -> [CareTask] {
        tasks.sorted { lhs, rhs in
            let left = lhs.dueAt ?? .distantFuture
            let right = rhs.dueAt ?? .distantFuture
            if left != right { return left < right }
            if lhs.priority.sortWeight != rhs.priority.sortWeight {
                return lhs.priority.sortWeight < rhs.priority.sortWeight
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

// MARK: - Merge

/// How a pulled task row meets a local one that has not been pushed yet.
///
/// Tasks need their own rule because the likeliest collision in the whole app
/// is two siblings ticking off the same errand, and that is agreement, not a
/// conflict: surfacing it as "1 change needs a look" would teach the family to
/// ignore the badge. Everything else, two people editing the same task's text
/// or due date in different directions, is a real disagreement and goes to a
/// human, the same way a dosage edit does.
///
/// Pure and separate from `SyncEngine` so the rule is testable without a store,
/// a remote or a container.
enum CareTaskMerge {
    enum Resolution: Sendable, Equatable {
        /// The pulled row wins outright.
        case takeServer
        /// This device's unpushed edit is the newer one. Keep it dirty; the
        /// outbox sends it on this same cycle.
        case keepLocal
        /// Two people edited the same task in different directions. Flag it.
        case conflict
    }

    static func resolve(
        localDirty: Bool,
        localUpdated: Date,
        localCompletedAt: Date?,
        serverUpdated: Date?,
        serverCompletedAt: Date?
    ) -> Resolution {
        // Nothing local to protect: the server row is simply the truth.
        guard localDirty else { return .takeServer }
        // A row with no server timestamp cannot be shown to be newer.
        guard let serverUpdated else { return .takeServer }

        // Genuine last-writer-wins, which is what `applyVisit` and `applyVital`
        // only claim to do: an older server row must not clobber a newer local
        // edit that is still sitting in the outbox.
        guard serverUpdated > localUpdated else { return .keepLocal }

        // Both sides ticked it off. Whoever actually did the errand first is
        // the one the record should name, and neither side loses anything the
        // other had.
        if let localCompletedAt, let serverCompletedAt {
            return serverCompletedAt <= localCompletedAt ? .takeServer : .keepLocal
        }

        return .conflict
    }
}
