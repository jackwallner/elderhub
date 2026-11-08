import Foundation
import Testing

@testable import Aging

@MainActor
struct ReminderPlacementTests {
    @Test func checkInReminderOnlyOnThePersonsOwnPhone() {
        let user = UUID()
        let own = Person(name: "Eleanor", relationship: "Mom")
        own.linkedUserID = user
        let other = Person(name: "Dad", relationship: "Dad")

        #expect(CheckInService.remindsOnThisPhone(person: own, signedInUserID: user, handedOverPersonID: nil, isRecipientMode: false))
        #expect(!CheckInService.remindsOnThisPhone(person: other, signedInUserID: user, handedOverPersonID: nil, isRecipientMode: false))
        #expect(!CheckInService.remindsOnThisPhone(person: own, signedInUserID: UUID(), handedOverPersonID: nil, isRecipientMode: false))
        #expect(CheckInService.remindsOnThisPhone(person: other, signedInUserID: nil, handedOverPersonID: other.id, isRecipientMode: true))
        #expect(!CheckInService.remindsOnThisPhone(person: own, signedInUserID: user, handedOverPersonID: other.id, isRecipientMode: true))
    }

    /// A caregiver's phone holds no record of its own, so the reminder an
    /// older version scheduled there is cleared.
    @Test func caregiverPhoneHoldsNoOwnRecord() {
        let user = UUID()
        let mom = Person(name: "Eleanor", relationship: "Mom")
        mom.linkedUserID = UUID()
        let dad = Person(name: "Dad", relationship: "Dad")
        #expect(!CheckInService.holdsOwnRecord(people: [mom, dad], signedInUserID: user))
        #expect(!CheckInService.holdsOwnRecord(people: [mom, dad], signedInUserID: nil))
        #expect(!CheckInService.holdsOwnRecord(people: [], signedInUserID: user))

        let me = Person(name: "Me", relationship: "Self")
        me.linkedUserID = user
        #expect(CheckInService.holdsOwnRecord(people: [mom, me], signedInUserID: user))
    }

    @Test func removedMemberForgetsTheCircle() {
        #expect(GroupService.membershipWasRevoked(rowCount: 0, hasCachedGroup: true, wasAuthenticated: true))
        #expect(!GroupService.membershipWasRevoked(rowCount: 0, hasCachedGroup: false, wasAuthenticated: true))
        #expect(!GroupService.membershipWasRevoked(rowCount: 1, hasCachedGroup: true, wasAuthenticated: true))
    }

    /// An anonymous query (no access token to send) sees no rows through RLS.
    /// That is not a removal, and must not wipe the circle or its outbox.
    @Test func anonymousEmptyAnswerKeepsTheCircle() {
        #expect(!GroupService.membershipWasRevoked(rowCount: 0, hasCachedGroup: true, wasAuthenticated: false))
    }
}
