import Foundation
import SwiftData
import Testing

@testable import Aging

@MainActor
@Suite("Care tasks")
struct CareTaskTests {

    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    // MARK: - Unknown raw values

    @Test func unknownPriorityAndRecurrenceFallBackRatherThanCrashing() {
        let task = CareTask(title: "Refill")
        // Stands in for a row written by a newer client. The whole reason these
        // are stored as strings is that this must not crash.
        task.priorityRaw = "urgent"
        task.recurrenceRaw = "fortnightly"
        #expect(task.priority == .normal)
        #expect(task.recurrence == .never)
    }

    // MARK: - Bucketing

    @Test func aDueTimeEarlierTodayStillReadsAsTodayNotOverdue() {
        let now = date(2026, 8, 4, 14)
        let task = CareTask(title: "Pharmacy", dueAt: date(2026, 8, 4, 9))
        // The failure this guards: a 9am task looking "late" at 2pm on the same
        // day, which turns the overdue section into noise by lunchtime.
        #expect(TaskPlanner.bucket(for: task, now: now, calendar: calendar()) == .today)
    }

    @Test func bucketsCoverOverdueTodayTomorrowThisWeekLaterAndUndated() {
        let now = date(2026, 8, 4, 14)
        let cal = calendar()

        func bucket(_ due: Date?) -> CareTaskBucket {
            let task = CareTask(title: "T")
            task.dueAt = due
            return TaskPlanner.bucket(for: task, now: now, calendar: cal)
        }

        #expect(bucket(date(2026, 8, 1)) == .overdue)
        #expect(bucket(date(2026, 8, 4, 23)) == .today)
        #expect(bucket(date(2026, 8, 5)) == .tomorrow)
        #expect(bucket(date(2026, 8, 8)) == .thisWeek)
        #expect(bucket(date(2026, 9, 1)) == .later)
        #expect(bucket(nil) == .someday)
    }

    @Test func openSectionsDropCompletedTasksTombstonesAndEmptyBuckets() {
        let now = date(2026, 8, 4, 14)
        let cal = calendar()

        let open = CareTask(title: "Call the pharmacy", dueAt: date(2026, 8, 1))
        let done = CareTask(title: "Book the dentist", dueAt: date(2026, 8, 1))
        done.completedAt = date(2026, 8, 2)
        let deleted = CareTask(title: "Old", dueAt: date(2026, 8, 1))
        deleted.deletedAt = date(2026, 8, 3)

        let sections = TaskPlanner.openSections([open, done, deleted], now: now, calendar: cal)

        #expect(sections.count == 1)
        #expect(sections[0].bucket == .overdue)
        #expect(sections[0].tasks.map(\.title) == ["Call the pharmacy"])
    }

    @Test func withinABucketSoonestFirstThenPriorityThenTitle() {
        let now = date(2026, 8, 4, 14)
        let cal = calendar()

        let sameDay = date(2026, 8, 4, 8)
        let earlier = CareTask(title: "Zebra", dueAt: date(2026, 8, 4, 7))
        let normal = CareTask(title: "Apple", dueAt: sameDay)
        let high = CareTask(title: "Banana", dueAt: sameDay, priority: .high)

        let sections = TaskPlanner.openSections([normal, high, earlier], now: now, calendar: cal)

        #expect(sections[0].tasks.map(\.title) == ["Zebra", "Banana", "Apple"])
    }

    @Test func todayShowsOverdueAndTodayButNotTomorrow() {
        let now = date(2026, 8, 4, 14)
        let cal = calendar()

        let late = CareTask(title: "Late", dueAt: date(2026, 8, 1))
        let today = CareTask(title: "Today", dueAt: date(2026, 8, 4, 20))
        let tomorrow = CareTask(title: "Tomorrow", dueAt: date(2026, 8, 5))
        let undated = CareTask(title: "Someday")

        let due = TaskPlanner.dueNow([late, today, tomorrow, undated], now: now, calendar: cal)

        #expect(due.map(\.title) == ["Late", "Today"])
    }

    @Test func recentlyCompletedIsNewestFirstAndWindowed() {
        let now = date(2026, 8, 4, 14)
        let cal = calendar()

        let recent = CareTask(title: "Recent")
        recent.completedAt = date(2026, 8, 2)
        let older = CareTask(title: "Older")
        older.completedAt = date(2026, 7, 20)
        let ancient = CareTask(title: "Ancient")
        ancient.completedAt = date(2026, 5, 1)
        let open = CareTask(title: "Open")

        let done = TaskPlanner.recentlyCompleted([older, recent, ancient, open], now: now, calendar: cal)

        #expect(done.map(\.title) == ["Recent", "Older"])
    }

    // MARK: - Assignment

    @Test func theIdWinsWheneverBothSidesHaveOne() {
        let me = UUID()
        let sibling = UUID()

        let mine = CareTask(title: "Order hearing aids", assigneeName: "Chris")
        mine.assigneeUserID = me
        let theirs = CareTask(title: "Book the audiologist", assigneeName: "Chris")
        theirs.assigneeUserID = sibling

        // Two siblings called Chris is exactly the case the name cannot answer,
        // so the id must not be second-guessed by it.
        #expect(TaskPlanner.isAssigned(mine, to: me, named: "Chris"))
        #expect(!TaskPlanner.isAssigned(theirs, to: me, named: "Chris"))
    }

    @Test func aTypedNameStillAssignsWhenNeitherSideHasAnId() {
        // The offline case: no member list was ever loaded, so the editor wrote
        // a name and no id. Matching has to be forgiving about case and spacing
        // because a human typed both halves.
        let task = CareTask(title: "Pick up the prescription", assigneeName: "  sarah ")
        #expect(task.assigneeUserID == nil)
        #expect(TaskPlanner.isAssigned(task, to: nil, named: "Sarah"))
        #expect(!TaskPlanner.isAssigned(task, to: nil, named: "Jack"))
    }

    @Test func aTaskWithAnIdFallsBackToTheNameWhileTheMemberListIsUnloaded() {
        let task = CareTask(title: "Refill", assigneeName: "Sarah")
        task.assigneeUserID = UUID()
        // `selfUserID` is nil until `loadMembers()` has run. Reading that as
        // "nothing is yours" would leave the Mine filter empty on launch.
        #expect(TaskPlanner.isAssigned(task, to: nil, named: "Sarah"))
    }

    @Test func anUnassignedTaskIsNobodysAndAnUnknownReaderOwnsNothing() {
        let unassigned = CareTask(title: "Call the pharmacy")
        #expect(!TaskPlanner.isAssigned(unassigned, to: UUID(), named: "Sarah"))
        // A reader with neither id nor name must not be handed every typed row.
        let assigned = CareTask(title: "Refill", assigneeName: "Sarah")
        #expect(!TaskPlanner.isAssigned(assigned, to: nil, named: ""))
    }

    @Test func filteringToOneAssigneeKeepsTheOrderTheListAlreadyHad() {
        let me = UUID()
        func task(_ title: String, _ owner: UUID?) -> CareTask {
            let task = CareTask(title: title, assigneeName: owner == nil ? "" : "Chris")
            task.assigneeUserID = owner
            return task
        }
        let tasks = [task("A", me), task("B", UUID()), task("C", nil), task("D", me)]

        let mine = TaskPlanner.assigned(tasks, to: me, named: "Chris")
        #expect(mine.map(\.title) == ["A", "D"])
    }

    // MARK: - Recurrence

    @Test func recurrenceStepsByWholeCalendarUnits() {
        let cal = calendar()
        let jan31 = date(2026, 1, 31)

        let monthly = TaskPlanner.nextDueDate(
            after: jan31, recurrence: .monthly, notBefore: jan31, calendar: cal
        )
        // Calendar arithmetic, not 30 fixed days: February clamps to the 28th.
        #expect(cal.component(.month, from: monthly!) == 2)
        #expect(cal.component(.day, from: monthly!) == 28)

        let never = TaskPlanner.nextDueDate(
            after: jan31, recurrence: .never, notBefore: jan31, calendar: cal
        )
        #expect(never == nil)
    }

    @Test func quarterlyAndHalfYearlyStepByMonthsNotWeeks() {
        let cal = calendar()
        let due = date(2026, 8, 15)

        let quarterly = TaskPlanner.nextDueDate(
            after: due, recurrence: .quarterly, notBefore: due, calendar: cal
        )
        #expect(cal.component(.year, from: quarterly!) == 2026)
        #expect(cal.component(.month, from: quarterly!) == 11)
        #expect(cal.component(.day, from: quarterly!) == 15)

        // The reorder-hearing-aids case, and the one the picker could not
        // express before: six months lands in the next year on the same day.
        let halfYearly = TaskPlanner.nextDueDate(
            after: due, recurrence: .halfYearly, notBefore: due, calendar: cal
        )
        #expect(cal.component(.year, from: halfYearly!) == 2027)
        #expect(cal.component(.month, from: halfYearly!) == 2)
        #expect(cal.component(.day, from: halfYearly!) == 15)
    }

    @Test func everyRecurrenceExceptNeverProducesAStep() {
        // Adding a case without a step would silently turn a repeat into a
        // one-off, which the family would only discover by not being reminded.
        for option in CareTaskRecurrence.allCases where option != .never {
            #expect(option.step != nil, "\(option.rawValue) has no step")
            #expect(!option.shortLabel.isEmpty)
        }
        #expect(CareTaskRecurrence.never.step == nil)
    }

    @Test func aRepeatMissedForMonthsSkipsForwardRatherThanSpawningSomethingAlreadyLate() {
        let cal = calendar()
        let due = date(2026, 1, 15)
        let now = date(2026, 8, 4)

        let next = TaskPlanner.nextDueDate(
            after: due, recurrence: .monthly, notBefore: now, calendar: cal
        )

        // The point: the follow-up must not be created already overdue.
        #expect(next! > now)
        #expect(cal.component(.month, from: next!) == 8)
        #expect(cal.component(.day, from: next!) == 15)
    }

    // MARK: - Completing

    @Test func completingARepeatingTaskKeepsTheHistoryAndQueuesTheNextOne() throws {
        let container = CareModelStore.makeInMemoryContainer()
        let context = container.mainContext
        let person = Person(name: "Mom")
        context.insert(person)

        let task = CareTask(
            title: "Replace hearing aid batteries",
            notes: "Size 312",
            dueAt: date(2026, 8, 1),
            priority: .high,
            recurrence: .weekly,
            assigneeName: "Sarah",
            person: person
        )
        context.insert(task)

        let followUp = task.markComplete(by: "Jack", at: date(2026, 8, 4), in: context)

        // The completed row is the history the family came for, so it must
        // survive rather than having its due date moved on.
        #expect(task.isDone)
        #expect(task.completedByName == "Jack")
        #expect(task.dueAt == date(2026, 8, 1))

        let next = try #require(followUp)
        #expect(next.title == task.title)
        #expect(next.notes == task.notes)
        #expect(next.priority == .high)
        #expect(next.assigneeName == "Sarah")
        #expect(next.completedAt == nil)
        #expect(next.dueAt! > date(2026, 8, 4))
        #expect(person.openTasks.map(\.id) == [next.id])
    }

    @Test func completingAOneOffTaskSpawnsNothing() {
        let container = CareModelStore.makeInMemoryContainer()
        let context = container.mainContext
        let person = Person(name: "Mom")
        context.insert(person)
        let task = CareTask(title: "Call the pharmacy", dueAt: date(2026, 8, 1), person: person)
        context.insert(task)

        let followUp = task.markComplete(by: "Jack", at: date(2026, 8, 4), in: context)

        #expect(followUp == nil)
        #expect(person.openTasks.isEmpty)
        #expect(person.liveTasks.count == 1)
    }

    @Test func reopeningATaskClearsWhoTickedItOff() {
        let container = CareModelStore.makeInMemoryContainer()
        let context = container.mainContext
        let task = CareTask(title: "Call the pharmacy")
        context.insert(task)
        task.markComplete(by: "Jack", in: context)

        task.markIncomplete(in: context)

        #expect(!task.isDone)
        #expect(task.completedByName.isEmpty)
    }

    // MARK: - Merge rule

    @Test func aCleanLocalRowAlwaysTakesTheServerCopy() {
        let resolution = CareTaskMerge.resolve(
            localDirty: false,
            localUpdated: date(2026, 8, 4, 12),
            localCompletedAt: nil,
            serverUpdated: date(2026, 8, 4, 10),
            serverCompletedAt: nil
        )
        #expect(resolution == .takeServer)
    }

    @Test func anOlderServerRowNeverClobbersANewerUnpushedEdit() {
        // This is the defect `applyVisit` and `applyVital` still have: a typed
        // note vanishing because a pull ran before the push.
        let resolution = CareTaskMerge.resolve(
            localDirty: true,
            localUpdated: date(2026, 8, 4, 12),
            localCompletedAt: nil,
            serverUpdated: date(2026, 8, 4, 10),
            serverCompletedAt: nil
        )
        #expect(resolution == .keepLocal)
    }

    @Test func twoSiblingsTickingOffTheSameErrandIsNotAConflict() {
        // The likeliest collision in the whole app. Surfacing it as "needs a
        // look" would teach the family to ignore the badge.
        let serverFirst = CareTaskMerge.resolve(
            localDirty: true,
            localUpdated: date(2026, 8, 4, 10),
            localCompletedAt: date(2026, 8, 4, 10),
            serverUpdated: date(2026, 8, 4, 12),
            serverCompletedAt: date(2026, 8, 4, 9)
        )
        #expect(serverFirst == .takeServer)

        let localFirst = CareTaskMerge.resolve(
            localDirty: true,
            localUpdated: date(2026, 8, 4, 10),
            localCompletedAt: date(2026, 8, 4, 8),
            serverUpdated: date(2026, 8, 4, 12),
            serverCompletedAt: date(2026, 8, 4, 9)
        )
        // Whoever actually did the errand first is the one the record names.
        #expect(localFirst == .keepLocal)
    }

    @Test func twoPeopleEditingTheSameTaskInDifferentDirectionsIsAConflict() {
        let resolution = CareTaskMerge.resolve(
            localDirty: true,
            localUpdated: date(2026, 8, 4, 10),
            localCompletedAt: nil,
            serverUpdated: date(2026, 8, 4, 12),
            serverCompletedAt: nil
        )
        #expect(resolution == .conflict)
    }

    // MARK: - Sync round trip

    @Test func aPulledTaskLandsWithItsAssigneeAndSchedule() async throws {
        let engine = SyncEngine(modelContainer: CareModelStore.makeInMemoryContainer())
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let dto = CareTaskDTO(
            id: UUID(), group_id: group, care_recipient_id: personID,
            title: "Refill the Lisinopril", notes: "90 day supply",
            due_at: date(2026, 8, 10), priority: CareTaskPriority.high.rawValue,
            recurrence: CareTaskRecurrence.monthly.rawValue,
            assignee_user_id: nil, assignee_name: "Sarah",
            completed_at: nil, completed_by_name: "", created_by_name: "Jack",
            updated_at: Date(), deleted_at: nil
        )
        try await remote.seed([dto])

        _ = await engine.sync(remote: remote, groupID: group)

        let snapshot = try #require(try await engine.careTaskSnapshotForTesting(id: dto.id))
        #expect(snapshot.title == "Refill the Lisinopril")
        #expect(snapshot.assigneeName == "Sarah")
        #expect(snapshot.priorityRaw == "high")
        #expect(snapshot.recurrenceRaw == "monthly")
        #expect(snapshot.isDirty == false)
    }

    @Test func aLocalTaskReachesTheServerAndSettles() async throws {
        let engine = SyncEngine(modelContainer: CareModelStore.makeInMemoryContainer())
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let taskID = try await engine.insertCareTaskForTesting(
            title: "Book the audiologist", personID: personID, groupID: group
        )
        await engine.enqueue(entity: .careTask, id: taskID, groupID: group)

        _ = await engine.sync(remote: remote, groupID: group)

        #expect(await remote.count(.careTask) == 1)
        let snapshot = try #require(try await engine.careTaskSnapshotForTesting(id: taskID))
        #expect(snapshot.isDirty == false)
    }

    @Test func aTombstonedTaskIsPushedBeforeItLeavesTheStore() async throws {
        let engine = SyncEngine(modelContainer: CareModelStore.makeInMemoryContainer())
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let taskID = try await engine.insertCareTaskForTesting(
            title: "Book the audiologist", personID: personID, groupID: group
        )
        try await engine.tombstoneCareTaskForTesting(id: taskID)
        await engine.enqueue(entity: .careTask, id: taskID, groupID: group)

        _ = await engine.sync(remote: remote, groupID: group)

        // The delete has to reach the family, which means the row survives
        // locally until the push has read it (`SyncableRecord.tombstone`).
        let pushed = try await remote.rows(CareTaskDTO.self)
        #expect(pushed.count == 1)
        #expect(pushed.first?.deleted_at != nil)
        #expect(try await engine.careTaskSnapshotForTesting(id: taskID) == nil)
    }
}

// MARK: - Test reach-ins

extension SyncEngine {
    struct CareTaskSnapshot: Sendable {
        var id: UUID
        var title: String
        var assigneeName: String
        var priorityRaw: String
        var recurrenceRaw: String
        var completedAt: Date?
        var isDirty: Bool
    }

    func insertCareTaskForTesting(title: String, personID: UUID, groupID: UUID?) throws -> UUID {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == personID })
        guard let person = try modelContext.fetch(descriptor).first else {
            throw TestReachInError.personNotFound
        }
        let task = CareTask(title: title, person: person)
        task.groupID = groupID
        task.isDirty = true
        modelContext.insert(task)
        try modelContext.save()
        return task.id
    }

    func tombstoneCareTaskForTesting(id: UUID) throws {
        let descriptor = FetchDescriptor<CareTask>(predicate: #Predicate { $0.id == id })
        guard let task = try modelContext.fetch(descriptor).first else { return }
        task.deletedAt = Date()
        task.isDirty = true
        try modelContext.save()
    }

    func careTaskSnapshotForTesting(id: UUID) throws -> CareTaskSnapshot? {
        let descriptor = FetchDescriptor<CareTask>(predicate: #Predicate { $0.id == id })
        guard let task = try modelContext.fetch(descriptor).first else { return nil }
        return CareTaskSnapshot(
            id: task.id, title: task.title, assigneeName: task.assigneeName,
            priorityRaw: task.priorityRaw, recurrenceRaw: task.recurrenceRaw,
            completedAt: task.completedAt, isDirty: task.isDirty
        )
    }
}
