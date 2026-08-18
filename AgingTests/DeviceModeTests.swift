import Foundation
import Testing

@testable import Aging

/// Handing the phone over, and getting it back.
///
/// The rules worth pinning down are the ones that would strand somebody: a
/// wrong code must refuse without switching, and removing the code must never
/// leave the handset in the recipient's view with nothing to unlock it.
@MainActor
struct DeviceModeTests {

    private func makeService() -> (DeviceModeService, UserDefaults) {
        let suite = UserDefaults(suiteName: "device-mode-\(UUID().uuidString)")!
        return (DeviceModeService(defaults: suite), suite)
    }

    @Test func startsAsTheCaregiverWithNoCode() {
        let (service, _) = makeService()
        #expect(service.mode == .caregiver)
        #expect(!service.isRecipientMode)
        #expect(service.allowsEditing)
        #expect(!service.hasPIN)
    }

    @Test func handingOverNeedsNoCodeAndBlocksEditing() {
        let (service, _) = makeService()
        service.handOver()
        #expect(service.isRecipientMode)
        #expect(!service.allowsEditing)
    }

    /// Without a code there is nothing to check, and the settings copy says so
    /// rather than implying the phone is locked.
    @Test func comingBackWithoutACodeAlwaysSucceeds() {
        let (service, _) = makeService()
        service.handOver()
        #expect(service.returnToCaregiver(pin: nil))
        #expect(service.mode == .caregiver)
    }

    @Test func theWrongCodeRefusesAndLeavesThePhoneWhereItWas() {
        let (service, _) = makeService()
        #expect(service.setPIN("1234"))
        service.handOver()

        #expect(!service.returnToCaregiver(pin: "9999"))
        #expect(service.isRecipientMode)

        #expect(service.returnToCaregiver(pin: "1234"))
        #expect(service.mode == .caregiver)
    }

    /// A missing code is not an empty code: `nil` must be refused outright
    /// rather than falling through the `hasPIN` guard.
    @Test func noCodeSuppliedIsRefusedOnceOneIsSet() {
        let (service, _) = makeService()
        service.setPIN("4321")
        service.handOver()
        #expect(!service.returnToCaregiver(pin: nil))
        #expect(service.isRecipientMode)
    }

    @Test func onlyFourDigitsAreAccepted() {
        let (service, _) = makeService()
        #expect(!service.setPIN("123"))
        #expect(!service.setPIN("12345"))
        #expect(!service.setPIN("12a4"))
        #expect(!service.hasPIN)
        #expect(service.setPIN("0000"))
        #expect(service.hasPIN)
    }

    /// The door-with-no-handle case. Clearing the code while handed over has to
    /// come back, or the phone is stuck on the check-in screen for good.
    @Test func removingTheCodeComesBackToTheCaregiver() {
        let (service, _) = makeService()
        service.setPIN("1111")
        service.handOver()

        service.clearPIN()

        #expect(!service.hasPIN)
        #expect(service.mode == .caregiver)
    }

    @Test func theCodeIsNotStoredInTheClear() {
        let (service, defaults) = makeService()
        service.setPIN("2468")

        let stored = defaults.dictionaryRepresentation().values.compactMap { $0 as? String }
        #expect(!stored.contains("2468"))
        #expect(defaults.data(forKey: "caregiverPINHash") != nil)
    }

    @Test func modeSurvivesARelaunch() {
        let suite = UserDefaults(suiteName: "device-mode-\(UUID().uuidString)")!
        let first = DeviceModeService(defaults: suite)
        first.setPIN("1357")
        first.handOver()

        let second = DeviceModeService(defaults: suite)
        #expect(second.isRecipientMode)
        #expect(second.hasPIN)
        #expect(second.verify(pin: "1357"))
    }

    // MARK: - Whose screen it is

    /// The whole point of naming the person: two parents on one handset, and
    /// the check-in screen previously had to guess between them.
    @Test func handingOverRemembersWhoWasHandedThePhone() {
        let (service, _) = makeService()
        let dad = UUID()
        service.handOver(to: dad)
        #expect(service.handedOverPersonID == dad)
        #expect(service.isRecipientMode)
    }

    @Test func theChosenPersonSurvivesARelaunch() {
        let suite = UserDefaults(suiteName: "device-mode-\(UUID().uuidString)")!
        let mom = UUID()
        DeviceModeService(defaults: suite).handOver(to: mom)

        #expect(DeviceModeService(defaults: suite).handedOverPersonID == mom)
    }

    /// Coming back ends that handover. Keeping the id would make the next
    /// hand-over silently reuse whoever held it last, which is the same
    /// wrong-person bug by a slower route.
    @Test func comingBackForgetsWhoWasHoldingIt() {
        let (service, _) = makeService()
        service.handOver(to: UUID())
        #expect(service.returnToCaregiver(pin: nil))
        #expect(service.handedOverPersonID == nil)
    }

    @Test func aRefusedCodeKeepsTheChosenPerson() {
        let (service, _) = makeService()
        let mom = UUID()
        service.setPIN("2468")
        service.handOver(to: mom)

        #expect(!service.returnToCaregiver(pin: "1111"))
        #expect(service.handedOverPersonID == mom)
        #expect(service.isRecipientMode)
    }

    /// Clearing the code drops the handset back to the caregiver, so it has to
    /// drop the handover with it.
    @Test func clearingTheCodeForgetsWhoWasHoldingIt() {
        let (service, _) = makeService()
        service.setPIN("9753")
        service.handOver(to: UUID())
        service.clearPIN()

        #expect(service.mode == .caregiver)
        #expect(service.handedOverPersonID == nil)
    }

    /// A handset with one record, or one handed over by a build that predates
    /// the choice, is not a broken handset.
    @Test func handingOverWithNobodyToChooseBetweenStillWorks() {
        let (service, _) = makeService()
        service.handOver()
        #expect(service.isRecipientMode)
        #expect(service.handedOverPersonID == nil)
    }
}
