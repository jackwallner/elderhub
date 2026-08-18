import Foundation
import SwiftData
import Testing

@testable import Aging

@MainActor
struct BillPlannerTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    private func makePerson(in context: ModelContext) -> Person {
        let person = Person(name: "Eleanor")
        context.insert(person)
        return person
    }

    private func makeBill(
        _ payee: String,
        amount: Double = 100,
        dueInDays: Int? = nil,
        recurrence: BillRecurrence = .monthly,
        isAutoPay: Bool = false,
        in context: ModelContext,
        person: Person
    ) -> Bill {
        let bill = Bill(
            payee: payee,
            amount: amount,
            recurrence: recurrence,
            dueAt: dueInDays.flatMap {
                Calendar.current.date(byAdding: .day, value: $0, to: Date())
            },
            isAutoPay: isAutoPay,
            person: person
        )
        context.insert(bill)
        return bill
    }

    // MARK: Recurrence

    @Test func quarterlyStepsThreeMonths() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let notBefore = calendar.date(from: DateComponents(year: 2026, month: 1, day: 16))!

        let next = BillPlanner.nextDueDate(after: start, recurrence: .quarterly, notBefore: notBefore)

        #expect(next == calendar.date(from: DateComponents(year: 2026, month: 4, day: 15)))
    }

    @Test func halfYearlyStepsSixMonths() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let notBefore = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!

        let next = BillPlanner.nextDueDate(after: start, recurrence: .halfYearly, notBefore: notBefore)

        #expect(next == calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
    }

    /// The reason the planner steps in a loop rather than adding one interval:
    /// a bill left unpaid for a year must not produce a follow-up that is
    /// already overdue on the day it is created.
    @Test func aLongNeglectedBillCatchesUpPastToday() {
        let calendar = Calendar.current
        let longAgo = calendar.date(byAdding: .month, value: -14, to: Date())!

        let next = BillPlanner.nextDueDate(after: longAgo, recurrence: .monthly)

        let unwrapped = next ?? .distantPast
        #expect(unwrapped > Date())
    }

    @Test func aOneOffBillHasNoNextDate() {
        #expect(BillPlanner.nextDueDate(after: Date(), recurrence: .never) == nil)
    }

    // MARK: Bucketing

    @Test func aBillPastItsDateIsOverdue() {
        let context = makeContext()
        let person = makePerson(in: context)
        let bill = makeBill("Sunrise", dueInDays: -2, in: context, person: person)

        #expect(BillPlanner.bucket(for: bill) == .overdue)
    }

    @Test func aBillInsideTheWeekIsDueSoonAndBeyondItIsLater() {
        let context = makeContext()
        let person = makePerson(in: context)
        let soon = makeBill("Duke Energy", dueInDays: 3, in: context, person: person)
        let later = makeBill("Property tax", dueInDays: 40, in: context, person: person)

        #expect(BillPlanner.bucket(for: soon) == .dueSoon)
        #expect(BillPlanner.bucket(for: later) == .upcoming)
    }

    @Test func aBillDueTodayIsDueSoonNotOverdue() {
        let context = makeContext()
        let person = makePerson(in: context)
        let bill = makeBill("Comcast", dueInDays: 0, in: context, person: person)

        #expect(BillPlanner.bucket(for: bill) == .dueSoon)
    }

    @Test func aBillWithNoDateIsNeverLate() {
        let context = makeContext()
        let person = makePerson(in: context)
        let bill = makeBill("Gardener", in: context, person: person)

        #expect(BillPlanner.bucket(for: bill) == .undated)
    }

    /// Autopay wins over the date. Without this, every direct debit eventually
    /// reads as overdue and the overdue section stops meaning anything.
    @Test func anAutoPayBillIsNeverOverdue() {
        let context = makeContext()
        let person = makePerson(in: context)
        let bill = makeBill("Medicare supplement", dueInDays: -30, isAutoPay: true, in: context, person: person)

        #expect(BillPlanner.bucket(for: bill) == .autoPay)
        #expect(BillPlanner.needingAttention([bill]).isEmpty)
    }

    // MARK: Today's list

    @Test func needingAttentionIsOverdueAndDueSoonOnly() {
        let context = makeContext()
        let person = makePerson(in: context)
        let overdue = makeBill("Sunrise", dueInDays: -2, in: context, person: person)
        let soon = makeBill("Duke Energy", dueInDays: 3, in: context, person: person)
        _ = makeBill("Property tax", dueInDays: 40, in: context, person: person)
        _ = makeBill("Gardener", in: context, person: person)
        _ = makeBill("Medicare", dueInDays: 1, isAutoPay: true, in: context, person: person)

        let due = BillPlanner.needingAttention(person.liveBills)

        #expect(due.map(\.payee) == [overdue.payee, soon.payee])
    }

    @Test func paidAndDeletedBillsAreNeverInTheAttentionList() {
        let context = makeContext()
        let person = makePerson(in: context)
        let paid = makeBill("Sunrise", dueInDays: -2, in: context, person: person)
        paid.paidAt = Date()
        let deleted = makeBill("Duke Energy", dueInDays: -1, in: context, person: person)
        deleted.deletedAt = Date()

        #expect(BillPlanner.needingAttention(person.liveBills).isEmpty)
    }

    // MARK: Marking paid

    /// The same rule `CareTask.markComplete` follows: the paid row is the
    /// history the family came for, so the next period is a new row.
    @Test func markingARecurringBillPaidCreatesTheNextOneAndKeepsThisOne() {
        let context = makeContext()
        let person = makePerson(in: context)
        let bill = makeBill("Sunrise", dueInDays: -1, recurrence: .monthly, in: context, person: person)

        let followUp = bill.markPaid(by: "Jack", in: context)

        #expect(bill.isPaid)
        #expect(bill.paidByName == "Jack")
        #expect(followUp?.payee == "Sunrise")
        #expect(followUp?.isPaid == false)
        #expect(followUp?.recurrence == .monthly)
        #expect((followUp?.dueAt ?? .distantPast) > Date())
        #expect(person.liveBills.count == 2)
    }

    @Test func markingAOneOffBillPaidCreatesNothing() {
        let context = makeContext()
        let person = makePerson(in: context)
        let bill = makeBill("Plumber", dueInDays: -1, recurrence: .never, in: context, person: person)

        let followUp = bill.markPaid(by: "Sarah", in: context)

        #expect(followUp == nil)
        #expect(person.liveBills.count == 1)
    }

    @Test func markingUnpaidClearsWhoPaidIt() {
        let context = makeContext()
        let person = makePerson(in: context)
        let bill = makeBill("Plumber", recurrence: .never, in: context, person: person)
        bill.markPaid(by: "Sarah", in: context)

        bill.markUnpaid(in: context)

        #expect(!bill.isPaid)
        #expect(bill.paidByName.isEmpty)
    }

    // MARK: Totals and summary

    @Test func theOutstandingTotalCountsOpenBillsIncludingAutoPay() {
        let context = makeContext()
        let person = makePerson(in: context)
        _ = makeBill("Sunrise", amount: 2450, dueInDays: -1, in: context, person: person)
        _ = makeBill("Medicare", amount: 189, dueInDays: 5, isAutoPay: true, in: context, person: person)
        let paid = makeBill("Comcast", amount: 90, dueInDays: -10, in: context, person: person)
        paid.paidAt = Date()

        #expect(BillPlanner.outstandingTotal(person.liveBills) == 2639)
    }

    @Test func theSummaryLineNamesOverdueSeparately() {
        let context = makeContext()
        let person = makePerson(in: context)
        _ = makeBill("Sunrise", dueInDays: -1, in: context, person: person)
        _ = makeBill("Duke Energy", dueInDays: 4, in: context, person: person)

        #expect(BillPlanner.summaryLine(person.liveBills) == "2 open · 1 overdue")
    }

    @Test func theSummaryLineSaysNothingDueWhenEverythingIsPaid() {
        let context = makeContext()
        let person = makePerson(in: context)
        let bill = makeBill("Sunrise", dueInDays: -1, in: context, person: person)
        bill.paidAt = Date()

        #expect(BillPlanner.summaryLine(person.liveBills) == "Nothing due")
    }

    // MARK: Sorting

    @Test func undatedBillsSortAfterDatedOnes() {
        let context = makeContext()
        let person = makePerson(in: context)
        _ = makeBill("Undated", in: context, person: person)
        _ = makeBill("Later", dueInDays: 20, in: context, person: person)
        _ = makeBill("Sooner", dueInDays: 2, in: context, person: person)

        let sorted = BillPlanner.sorted(person.liveBills)

        #expect(sorted.map(\.payee) == ["Sooner", "Later", "Undated"])
    }

    // MARK: The boundary that is not a style choice

    /// A bill is a record, never an instruction and never a payment. Nothing in
    /// the model may grow a field that pays, chases or authenticates.
    @Test func aBillCarriesNoCredentialField() {
        let context = makeContext()
        let person = makePerson(in: context)
        let bill = makeBill("Sunrise", in: context, person: person)

        let mirror = Mirror(reflecting: bill)
        let names = mirror.children.compactMap(\.label).map { $0.lowercased() }
        for banned in ["account", "password", "login", "card", "routing", "iban", "token"] {
            #expect(!names.contains { $0.contains(banned) })
        }
    }
}
