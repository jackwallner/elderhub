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

    @Test func removedMemberForgetsTheCircle() {
        #expect(GroupService.membershipWasRevoked(rowCount: 0, hasCachedGroup: true))
        #expect(!GroupService.membershipWasRevoked(rowCount: 0, hasCachedGroup: false))
        #expect(!GroupService.membershipWasRevoked(rowCount: 1, hasCachedGroup: true))
    }
}
