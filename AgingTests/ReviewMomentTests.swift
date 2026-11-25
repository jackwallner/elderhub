import Foundation
import SwiftData
import Testing

@testable import Aging

/// The one moment the rating prompt may follow: something just done on Today
/// leaves nothing outstanding for anyone. A bad or partial day never asks.
@MainActor
struct ReviewMomentTests {
    private var noon: Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    }

    private var eightToday: Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
    }

    /// Mom, one 8am dose, logged with `status` (or not logged at all).
    private func digests(doseLogged status: DoseStatus?) -> [PersonDigest] {
        let context = ModelContext(CareModelStore.makeInMemoryContainer())
        let mom = Person(name: "Eleanor", relationship: "Mom")
        context.insert(mom)
        let medication = Medication(name: "Metformin", person: mom)
        medication.scheduleMinutes = [8 * 60]
        context.insert(medication)
        if let status {
            context.insert(DoseLog(scheduledAt: eightToday, status: status, recordedBy: "Sarah", medication: medication))
        }
        return TodayDigest.build(for: [mom], on: noon)
    }

    @Test func theLastDoseTakenIsAGoodMoment() {
        let day = digests(doseLogged: .taken)
        #expect(day.allSatisfy(\.isClear), "precondition: the day is done")
        #expect(ReviewPrompt.isGoodMoment(.dose(.taken), digests: day))
    }

    @Test func aTaskOrBillThatClearsTheDayIsAGoodMoment() {
        let day = digests(doseLogged: .taken)
        #expect(ReviewPrompt.isGoodMoment(.taskDone, digests: day))
        #expect(ReviewPrompt.isGoodMoment(.billPaid, digests: day))
    }

    @Test func aSkippedOrMissedDoseNeverAsks() {
        let skipped = digests(doseLogged: .skipped)
        #expect(skipped.allSatisfy(\.isClear), "precondition: skipped is an answered slot")
        #expect(!ReviewPrompt.isGoodMoment(.dose(.skipped), digests: skipped))
        #expect(!ReviewPrompt.isGoodMoment(.dose(.missed), digests: digests(doseLogged: .missed)))
    }

    @Test func somethingStillOverdueNeverAsks() {
        let day = digests(doseLogged: nil)
        #expect(day.first?.overdueSlots.count == 1, "precondition: the 8am dose is overdue")
        #expect(!ReviewPrompt.isGoodMoment(.taskDone, digests: day))
        #expect(!ReviewPrompt.isGoodMoment(.billPaid, digests: day))
        #expect(!ReviewPrompt.isGoodMoment(.dose(.taken), digests: day))
    }

    @Test func nobodyOnTheRecordNeverAsks() {
        #expect(!ReviewPrompt.isGoodMoment(.dose(.taken), digests: []))
    }
}
