import Foundation
import SwiftData
import Testing

@testable import Aging

/// The one automatic rating ask comes after a tick-off on Today that left
/// nothing outstanding for anyone. These pin the moment itself: a finished
/// day asks, a day with anything still open does not.
@MainActor
struct ReviewMomentTests {
    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    private var noon: Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    }

    /// A person with one 8am tablet, logged with `status` (nil: not logged).
    private func person(named name: String, eightAM status: DoseStatus?, in context: ModelContext) -> Person {
        let person = Person(name: name, relationship: "Mom")
        context.insert(person)
        let med = Medication(name: "Metformin", person: person)
        med.scheduleMinutes = [8 * 60]
        context.insert(med)
        if let status, let slot = ScheduleEngine.slots(for: person, on: noon).first {
            context.insert(DoseLog(scheduledAt: slot.scheduledAt, status: status, medication: med))
        }
        return person
    }

    @Test func everyDoseTakenForEveryoneIsTheGoodMoment() {
        let context = makeContext()
        let mom = person(named: "Eleanor", eightAM: .taken, in: context)
        let dad = person(named: "Frank", eightAM: .taken, in: context)
        #expect(ReviewPrompt.isGoodMoment(TodayDigest.build(for: [mom, dad], on: noon)))
    }

    @Test func anOverdueDoseForAnyoneIsNotTheMoment() {
        let context = makeContext()
        let mom = person(named: "Eleanor", eightAM: .taken, in: context)
        let dad = person(named: "Frank", eightAM: nil, in: context)
        #expect(ReviewPrompt.isGoodMoment(TodayDigest.build(for: [mom], on: noon)))
        #expect(!ReviewPrompt.isGoodMoment(TodayDigest.build(for: [mom, dad], on: noon)))
    }

    @Test func anOutstandingTaskIsNotTheMoment() {
        let context = makeContext()
        let mom = person(named: "Eleanor", eightAM: .taken, in: context)
        context.insert(CareTask(title: "Call the pharmacy", dueAt: noon.addingTimeInterval(-3600), person: mom))
        #expect(!ReviewPrompt.isGoodMoment(TodayDigest.build(for: [mom], on: noon)))
    }

    @Test func aCheckInStillToPressIsNotTheMoment() {
        let context = makeContext()
        let mom = person(named: "Eleanor", eightAM: .taken, in: context)
        let digests = TodayDigest.build(for: [mom], on: noon, checkInState: { _ in (true, false) })
        #expect(!ReviewPrompt.isGoodMoment(digests))
    }

    @Test func nobodyToLookAfterIsNotTheMoment() {
        #expect(!ReviewPrompt.isGoodMoment([]))
    }
}
