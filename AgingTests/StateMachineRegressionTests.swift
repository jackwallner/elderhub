import Foundation
import SwiftData
import Testing

@testable import Aging

/// Regression tests for the 2026-11-24 state machine audit
/// (`project-docs/audits/state-machines-2026-11-24*.md`).
@MainActor
struct StateMachineRegressionTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func preconditions() {
        #expect(Self.calendar.range(of: .day, in: .month, for: day(2027, 2, 1))?.count == 28)
        #expect(Self.calendar.date(byAdding: .month, value: 2, to: day(2027, 1, 31)) == day(2027, 3, 31))
    }

    // MARK: B1. A late-paid month-end bill or task keeps its day

    @Test func lateBillDueOnThe31stKeepsItsDay() {
        preconditions()
        let next = BillPlanner.nextDueDate(
            after: day(2027, 1, 31), recurrence: .monthly,
            notBefore: day(2027, 3, 5), calendar: Self.calendar
        )
        #expect(next == day(2027, 3, 31))
    }

    @Test func lateTaskDueOnThe31stKeepsItsDay() {
        preconditions()
        let next = TaskPlanner.nextDueDate(
            after: day(2027, 1, 31), recurrence: .monthly,
            notBefore: day(2027, 3, 5), calendar: Self.calendar
        )
        #expect(next == day(2027, 3, 31))
    }

    @Test func lateQuarterlyBillKeepsItsDay() {
        preconditions()
        let next = BillPlanner.nextDueDate(
            after: day(2026, 11, 30), recurrence: .quarterly,
            notBefore: day(2027, 3, 1), calendar: Self.calendar
        )
        #expect(next == day(2027, 5, 30))
    }

    @Test func onTimeBillDueOnThe31stStillGoesToTheEndOfFebruary() {
        preconditions()
        let next = BillPlanner.nextDueDate(
            after: day(2027, 1, 31), recurrence: .monthly,
            notBefore: day(2027, 1, 30), calendar: Self.calendar
        )
        #expect(next == day(2027, 2, 28))
    }

    @Test func lateMidMonthBillStillKeepsItsDay() {
        preconditions()
        let next = BillPlanner.nextDueDate(
            after: day(2027, 1, 15), recurrence: .monthly,
            notBefore: day(2027, 3, 20), calendar: Self.calendar
        )
        #expect(next == day(2027, 4, 15))
    }

    @Test func weeklyAndDailyStepsAreUnchanged() {
        let weekly = TaskPlanner.nextDueDate(
            after: day(2027, 3, 1), recurrence: .weekly,
            notBefore: day(2027, 3, 16), calendar: Self.calendar
        )
        #expect(weekly == day(2027, 3, 22))
        let daily = TaskPlanner.nextDueDate(
            after: day(2027, 3, 1), recurrence: .daily,
            notBefore: day(2027, 3, 3, hour: 10), calendar: Self.calendar
        )
        #expect(daily == day(2027, 3, 4))
    }

    /// Upgrade: a follow-up an earlier build already wrote keeps the date it
    /// was stored with. Nothing rewrites rows the family can see.
    @Test func aStoredFollowUpKeepsItsDate() {
        let context = ModelContext(CareModelStore.makeInMemoryContainer())
        let person = Person(name: "Eleanor")
        context.insert(person)
        let device = Calendar.current
        let stored = device.date(from: DateComponents(year: 2027, month: 2, day: 28, hour: 12))!
        let bill = Bill(payee: "Rent", amount: 900, recurrence: .monthly, dueAt: stored, person: person)
        context.insert(bill)

        let next = bill.markPaid(by: "Sarah", at: stored, in: context)

        #expect(bill.dueAt == stored)
        #expect(next?.dueAt.map { device.component(.day, from: $0) } == 28)
        #expect(next?.dueAt.map { device.component(.month, from: $0) } == 3)
    }
}
