import Foundation
import SwiftData
import Testing

@testable import Aging

// State machine audit repro suite, 2026-11-24. Kept out of the test target:
// copy it into AgingTests/ to run it. Failing tests are expected on the
// audited commit (74bec1f): each one asserts the promised behaviour. Every test
// asserts its preconditions first, and each claim has a passing control.

@MainActor
@Suite(.serialized)
struct StateMachineAuditRepro {
    /// Fixed calendar and zone, so the month lengths the claims lean on do not
    /// depend on the runner.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func preconditions() {
        // February 2027 has 28 days, and two calendar months after 31 January
        // is 31 March: the dates the claims are judged against are real.
        #expect(Self.calendar.range(of: .day, in: .month, for: day(2027, 2, 1))?.count == 28)
        #expect(Self.calendar.date(byAdding: .month, value: 2, to: day(2027, 1, 31)) == day(2027, 3, 31))
    }

    // MARK: B1. A late-paid month-end bill or task comes back on the 28th

    /// Rent due on the 31st, paid late on 5 March: the next one is due on
    /// 31 March. The planner steps 31 Jan -> 28 Feb -> 28 Mar instead.
    @Test func lateBillDueOnThe31stKeepsItsDay() {
        preconditions()
        let next = BillPlanner.nextDueDate(
            after: day(2027, 1, 31), recurrence: .monthly,
            notBefore: day(2027, 3, 5), calendar: Self.calendar
        )
        #expect(next == day(2027, 3, 31), "a bill due on the 31st must not move to the 28th")
    }

    @Test func lateTaskDueOnThe31stKeepsItsDay() {
        preconditions()
        let next = TaskPlanner.nextDueDate(
            after: day(2027, 1, 31), recurrence: .monthly,
            notBefore: day(2027, 3, 5), calendar: Self.calendar
        )
        #expect(next == day(2027, 3, 31), "a task due on the 31st must not move to the 28th")
    }

    /// Quarterly from 30 November, paid the following June: 30 May, not 28 May.
    @Test func lateQuarterlyBillKeepsItsDay() {
        preconditions()
        let next = BillPlanner.nextDueDate(
            after: day(2026, 11, 30), recurrence: .quarterly,
            notBefore: day(2027, 3, 1), calendar: Self.calendar
        )
        #expect(next == day(2027, 5, 30), "a quarterly bill due on the 30th must not move to the 28th")
    }

    /// Control: paid on time, the next one really is the end of February.
    @Test func controlOnTimeBillDueOnThe31stGoesToTheEndOfFebruary() {
        preconditions()
        let next = BillPlanner.nextDueDate(
            after: day(2027, 1, 31), recurrence: .monthly,
            notBefore: day(2027, 1, 30), calendar: Self.calendar
        )
        #expect(next == day(2027, 2, 28))
    }

    /// Control: a mid-month bill paid late keeps its day already.
    @Test func controlLateMidMonthBillKeepsItsDay() {
        preconditions()
        let next = BillPlanner.nextDueDate(
            after: day(2027, 1, 15), recurrence: .monthly,
            notBefore: day(2027, 3, 20), calendar: Self.calendar
        )
        #expect(next == day(2027, 4, 15))
    }

    // MARK: B2. Once a month-end series passes February it stays on the 28th

    /// The paid February row is the only record of the series, and it says
    /// the 28th, so every later month is due on the 28th. Proves the drift;
    /// the fix needs the series' day stored on the row (held for Jack).
    @Test func monthEndSeriesReturnsToThe31stAfterFebruary() {
        preconditions()
        let context = ModelContext(CareModelStore.makeInMemoryContainer())
        let person = Person(name: "Eleanor")
        context.insert(person)
        let device = Calendar.current
        let januaryDue = device.date(from: DateComponents(year: 2027, month: 1, day: 31, hour: 12))!
        let january = Bill(payee: "Rent", amount: 900, recurrence: .monthly, dueAt: januaryDue, person: person)
        context.insert(january)

        // `markPaid` uses the device calendar, so compare calendar days in it.
        let february = january.markPaid(by: "Sarah", at: day(2027, 1, 30), in: context)
        #expect(february?.dueAt.map { device.component(.day, from: $0) } == 28)
        let march = february?.markPaid(by: "Sarah", at: day(2027, 2, 27), in: context)
        #expect(march?.dueAt.map { device.component(.day, from: $0) } == 31,
                "the series is due on the 31st; February only clamps it")
    }
}
