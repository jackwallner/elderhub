import Foundation

// MARK: - Buckets

/// Where an unpaid bill sits relative to now.
///
/// Coarser than a countdown on purpose, and the same shape as
/// `CareTaskBucket`: someone glancing at the list wants "is this late, is it
/// coming up, or is it a while off yet".
enum BillBucket: String, CaseIterable, Identifiable, Sendable {
    case overdue, dueSoon, upcoming, undated, autoPay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overdue: return "Overdue"
        case .dueSoon: return "Due soon"
        case .upcoming: return "Later"
        case .undated: return "No date"
        case .autoPay: return "On autopay"
        }
    }

    /// Ascending, so a plain sort produces the order the list renders in.
    var sortWeight: Int {
        switch self {
        case .overdue: return 0
        case .dueSoon: return 1
        case .upcoming: return 2
        case .undated: return 3
        case .autoPay: return 4
        }
    }
}

// MARK: - Planner

/// Pure functions over already-fetched `Bill` rows: no `ModelContext`, no
/// fetching, no network, exactly like `TaskPlanner` and `ScheduleEngine`. The
/// calendar arithmetic and the bucketing are the parts worth testing, and they
/// are all here rather than spread through the views.
///
/// Nothing in this file pays a bill, warns anybody, or decides that a family is
/// behind on anything. It sorts rows a human entered into groups a human can
/// read (I6).
enum BillPlanner {

    /// How close counts as "due soon".
    static let dueSoonWindowDays = 7

    // MARK: Recurrence

    /// The next occurrence at or after `notBefore`, stepping by whole calendar
    /// units from `date`.
    ///
    /// Steps repeatedly rather than adding one interval, so a quarterly invoice
    /// that went a year unticked does not spawn a follow-up that is already
    /// overdue the moment it is created. Same guard, and same reasoning, as
    /// `TaskPlanner.nextDueDate`.
    static func nextDueDate(
        after date: Date,
        recurrence: BillRecurrence,
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

    // MARK: Bucketing

    @MainActor
    static func bucket(
        for bill: Bill,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BillBucket {
        // Autopay first, before the date is even looked at. Something the bank
        // handles is worth having written down and is never a job somebody is
        // late on, and calling it overdue is how a list stops being believed.
        if bill.isAutoPay { return .autoPay }
        guard let dueAt = bill.dueAt else { return .undated }

        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: dueAt)
        if due < today { return .overdue }

        let days = calendar.dateComponents([.day], from: today, to: due).day ?? 0
        return days <= dueSoonWindowDays ? .dueSoon : .upcoming
    }

    /// Unpaid bills that want attention now: late, or inside the next week.
    /// Autopay and undated rows are deliberately not here, because the Today
    /// tab is a list of things to do.
    @MainActor
    static func needingAttention(
        _ bills: [Bill],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Bill] {
        sorted(
            bills.filter { bill in
                guard bill.deletedAt == nil, !bill.isPaid else { return false }
                let slot = bucket(for: bill, now: now, calendar: calendar)
                return slot == .overdue || slot == .dueSoon
            }
        )
    }

    /// Every open bill, grouped and in render order. Empty buckets are dropped
    /// rather than shown as headers over nothing.
    @MainActor
    static func sections(
        _ bills: [Bill],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [(bucket: BillBucket, bills: [Bill])] {
        let open = bills.filter { $0.deletedAt == nil && !$0.isPaid }
        return Dictionary(grouping: open) { bucket(for: $0, now: now, calendar: calendar) }
            .map { (bucket: $0.key, bills: sorted($0.value)) }
            .sorted { $0.bucket.sortWeight < $1.bucket.sortWeight }
    }

    /// Recently paid, newest first. Bounded by a window rather than a count, so
    /// the section stays a record of the last couple of months instead of
    /// growing into a second full list. Same rule as `recentlyCompleted`.
    @MainActor
    static func recentlyPaid(
        _ bills: [Bill],
        now: Date = Date(),
        within days: Int = 60,
        calendar: Calendar = .current
    ) -> [Bill] {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: now) else { return [] }
        return bills
            .filter { $0.deletedAt == nil }
            .compactMap { bill in bill.paidAt.map { (bill, $0) } }
            .filter { $0.1 >= cutoff }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Dated first and soonest first, then undated, then by payee. Undated rows
    /// sort last within their group rather than reading as due at the epoch.
    @MainActor
    static func sorted(_ bills: [Bill]) -> [Bill] {
        bills.sorted { lhs, rhs in
            switch (lhs.dueAt, rhs.dueAt) {
            case let (l?, r?):
                if l != r { return l < r }
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            case (nil, nil):
                break
            }
            return lhs.payee.localizedCaseInsensitiveCompare(rhs.payee) == .orderedAscending
        }
    }

    // MARK: Totals

    /// What the open bills add up to.
    ///
    /// One currency, the device's, and no conversion: this is an aid to reading
    /// a list somebody typed, not a financial statement. Autopay rows are
    /// included, because the money still leaves the account.
    @MainActor
    static func outstandingTotal(_ bills: [Bill]) -> Double {
        bills
            .filter { $0.deletedAt == nil && !$0.isPaid }
            .reduce(0) { $0 + $1.amount }
    }

    /// A one-line summary for the hub tile and the Today section header.
    @MainActor
    static func summaryLine(
        _ bills: [Bill],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let open = bills.filter { $0.deletedAt == nil && !$0.isPaid }
        guard !open.isEmpty else { return "Nothing due" }

        let overdue = open.filter { bucket(for: $0, now: now, calendar: calendar) == .overdue }
        let countPart = open.count == 1 ? "1 open" : "\(open.count) open"
        guard !overdue.isEmpty else { return countPart }
        return "\(countPart) · \(overdue.count) overdue"
    }
}
