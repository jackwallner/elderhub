import Foundation
import SwiftData
import Testing

@testable import Aging

/// The check-in settings screen saves when it is left, so every caregiver who
/// only looked at Mom's window wrote the row: a newer timestamp over whatever a
/// sibling had just agreed, and their own time zone, which the server judges the
/// window in, in place of the one it was agreed in.
@MainActor
struct CheckInSettingsWriteTests {

    private func makeContext() -> ModelContext {
        ModelContext(CareModelStore.makeInMemoryContainer())
    }

    private let newYork = TimeZone(identifier: "America/New_York")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    private func person(in context: ModelContext, group: UUID? = nil) -> Person {
        let person = Person(name: "Eleanor", relationship: "Mom")
        person.groupID = group
        context.insert(person)
        return person
    }

    private func row(for person: Person, in context: ModelContext) -> CheckInSettings? {
        let id = person.id
        return (try? context.fetch(FetchDescriptor<CheckInSettings>(predicate: #Predicate { $0.personID == id })))?.first
    }

    @discardableResult
    private func write(
        _ person: Person,
        in context: ModelContext,
        enabled: Bool = true,
        start: Int = 8 * 60,
        end: Int = 20 * 60,
        grace: Int = 60,
        zone: TimeZone,
        now: Date = Date()
    ) -> Bool {
        CheckInService.writeSettings(
            in: context, for: person, enabled: enabled, startMinute: start,
            endMinute: end, graceMinutes: grace, timeZone: zone, now: now
        )
    }

    @Test func agreeingAWindowWritesItWithTheZoneItWasAgreedIn() {
        let context = makeContext()
        let mom = person(in: context)

        #expect(write(mom, in: context, zone: newYork))

        let settings = row(for: mom, in: context)
        #expect(settings?.enabled == true)
        #expect(settings?.windowStartMinute == 8 * 60)
        #expect(settings?.windowEndMinute == 20 * 60)
        #expect(settings?.timeZoneIdentifier == "America/New_York")
        #expect(settings?.isDirty == true)
    }

    @Test func leavingTheScreenWithoutChangingAnythingLeavesTheTimeZoneAlone() {
        let context = makeContext()
        let mom = person(in: context)
        write(mom, in: context, zone: newYork)

        // A sibling in another city opens the screen and walks away.
        #expect(write(mom, in: context, zone: losAngeles) == false)

        #expect(row(for: mom, in: context)?.timeZoneIdentifier == "America/New_York")
    }

    @Test func leavingTheScreenWithoutChangingAnythingDoesNotBumpTheRow() {
        let context = makeContext()
        let mom = person(in: context)
        let agreed = Date(timeIntervalSince1970: 1_700_000_000)
        write(mom, in: context, zone: newYork, now: agreed)
        // What the engine does once the row has reached the server.
        row(for: mom, in: context)?.isDirty = false

        #expect(write(mom, in: context, zone: newYork, now: agreed.addingTimeInterval(3600)) == false)

        let settings = row(for: mom, in: context)
        #expect(settings?.updatedAt == agreed)
        #expect(settings?.isDirty == false)
    }

    @Test func movingTheWindowIsWritten() {
        let context = makeContext()
        let mom = person(in: context)
        write(mom, in: context, zone: newYork)

        #expect(write(mom, in: context, end: 21 * 60, zone: newYork))

        #expect(row(for: mom, in: context)?.windowEndMinute == 21 * 60)
    }

    @Test func changingTheGraceIsWritten() {
        let context = makeContext()
        let mom = person(in: context)
        write(mom, in: context, zone: newYork)

        #expect(write(mom, in: context, grace: 120, zone: newYork))

        #expect(row(for: mom, in: context)?.graceMinutes == 120)
    }

    @Test func turningItOffIsWritten() {
        let context = makeContext()
        let mom = person(in: context)
        write(mom, in: context, zone: newYork)

        #expect(write(mom, in: context, enabled: false, zone: newYork))

        #expect(row(for: mom, in: context)?.enabled == false)
    }

    @Test func lookingAtAPersonWhoseCheckInWasNeverAgreedWritesNothing() {
        let context = makeContext()
        let mom = person(in: context)

        #expect(write(mom, in: context, enabled: false, zone: losAngeles) == false)

        #expect(row(for: mom, in: context) == nil)
    }

    @Test func aRowThatJoinsTheCircleIsWrittenEvenWhenTheWindowIsTheSame() {
        let context = makeContext()
        let mom = person(in: context)
        write(mom, in: context, zone: newYork)

        mom.groupID = UUID()

        #expect(write(mom, in: context, zone: newYork))
        #expect(row(for: mom, in: context)?.groupID == mom.groupID)
    }
}
