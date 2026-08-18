import Foundation
import Testing

@testable import Aging

@MainActor
struct CareEventTests {

    // MARK: Unknown kind

    @Test func unknownKindRawFallsBackToOtherRatherThanCrashing() {
        let event = CareEvent(kind: .fall)
        // Stands in for a row written by a newer client with a kind this
        // build has never heard of. The whole reason enums are stored as
        // strings is that this must not crash.
        event.kindRaw = "seizure"
        #expect(event.kind == .other)
    }

    // MARK: Month grouping

    @Test func monthGroupingRespectsTheGivenTimeZone() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 23, minute: 30))!

        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        let event = CareEvent(kind: .symptom, occurredAt: date)

        let inUTC = CareEvent.groupedByMonth([event], calendar: utc)
        let inTokyo = CareEvent.groupedByMonth([event], calendar: tokyo)

        #expect(utc.component(.month, from: inUTC[0].month) == 1)
        // The same instant is already the next day, and the next month, in
        // Tokyo (UTC+9). Grouping must follow the calendar it is given, not
        // whatever zone happened to produce the timestamp.
        #expect(tokyo.component(.month, from: inTokyo[0].month) == 2)
    }

    @Test func monthGroupingSortsNewestMonthAndNewestEntryFirst() {
        let calendar = Calendar.current
        let jan = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let febEarly = calendar.date(from: DateComponents(year: 2026, month: 2, day: 3))!
        let febLate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 20))!

        let events = [
            CareEvent(kind: .fall, occurredAt: jan),
            CareEvent(kind: .symptom, occurredAt: febEarly),
            CareEvent(kind: .mood, occurredAt: febLate)
        ]

        let groups = CareEvent.groupedByMonth(events, calendar: calendar)

        #expect(groups.count == 2)
        #expect(calendar.component(.month, from: groups[0].month) == 2)
        #expect(groups[0].events.map(\.kind) == [.mood, .symptom])
        #expect(calendar.component(.month, from: groups[1].month) == 1)
    }

    // MARK: Sync round trip

    @Test func recordedBySurvivesASyncRoundTrip() async throws {
        let engine = SyncEngine(modelContainer: CareModelStore.makeInMemoryContainer())
        let remote = FakeRemote()
        let group = UUID()

        let personID = try await engine.insertPersonForTesting(name: "Mom", groupID: group)
        let dto = CareEventDTO(
            id: UUID(), group_id: group, care_recipient_id: personID,
            kind: CareEventKind.fall.rawValue, occurred_at: Date(), severity: 3,
            note: "Slipped in the kitchen", recorded_by_name: "Sarah",
            updated_at: Date(), deleted_at: nil
        )
        try await remote.seed([dto])

        _ = await engine.sync(remote: remote, groupID: group)

        let snapshot = try await engine.careEventSnapshotForTesting(id: dto.id)
        #expect(snapshot?.recordedBy == "Sarah")
    }
}
