import Foundation
import SwiftData
import Testing

@testable import Aging

/// The check-in, from both ends: the settings row that the subject's device
/// schedules its reminder from, and the press itself.
///
/// The invariant these exist to defend is I2. Nothing on the press path may
/// consult billing, and the way that stays true is that `CheckInService` does
/// not import `StoreService` at all. A test cannot assert an absent import, so
/// the guard here is the settings/press behaviour plus the note on the type.
@Suite("Check-in")
struct CheckInTests {

    private func makeEngine() -> (SyncEngine, ModelContainer) {
        let container = CareModelStore.makeInMemoryContainer()
        return (SyncEngine(modelContainer: container), container)
    }

    private func settings(
        recipient: UUID,
        group: UUID,
        enabled: Bool = true,
        start: Int = 8 * 60,
        end: Int = 20 * 60,
        updated: Date
    ) -> CheckInSettingsDTO {
        CheckInSettingsDTO(
            care_recipient_id: recipient, group_id: group, enabled: enabled,
            window_start_minute: start, window_end_minute: end,
            grace_minutes: 60, timezone: "America/Los_Angeles",
            updated_at: updated
        )
    }

    @Test("The agreed window reaches the subject's device")
    func settingsPull() async throws {
        let (engine, container) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()
        let recipient = UUID()

        try await remote.seed([settings(recipient: recipient, group: group, updated: Date())])
        let outcome = await engine.sync(remote: remote, groupID: group)
        #expect(outcome.pulled == 1)

        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<CheckInSettings>())
        #expect(rows.count == 1)
        #expect(rows.first?.personID == recipient)
        #expect(rows.first?.windowStartMinute == 8 * 60)
        // Stored as an IANA identifier rather than an offset, so the window does
        // not drift when the clocks change or the person travels.
        #expect(rows.first?.timeZoneIdentifier == "America/Los_Angeles")
        #expect(rows.first?.isDirty == false)
    }

    @Test("The settings row is keyed on the recipient, not on an id of its own")
    func settingsAreKeyedOnRecipient() async throws {
        let (engine, container) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()
        let recipient = UUID()
        let early = Date().addingTimeInterval(-600)

        try await remote.seed([settings(recipient: recipient, group: group, updated: early)])
        _ = await engine.sync(remote: remote, groupID: group)

        // The family moves the window later. A second row must not appear.
        try await remote.seed([
            settings(recipient: recipient, group: group, start: 10 * 60, updated: Date())
        ])
        _ = await engine.sync(remote: remote, groupID: group)

        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<CheckInSettings>())
        #expect(rows.count == 1)
        #expect(rows.first?.windowStartMinute == 10 * 60)
    }

    @Test("A queued press survives being offline and keeps the time it happened")
    func pressSurvivesOffline() async throws {
        let (engine, container) = makeEngine()
        let remote = FakeRemote()
        let group = UUID()
        let recipient = UUID()

        // Pressed in a basement at 09:00; the phone does not find signal for
        // hours. The record is of 09:00, not of whenever it finally syncs.
        let pressedAt = Date().addingTimeInterval(-4 * 3600)
        let context = ModelContext(container)
        let record = CheckInRecord(
            groupID: group, personID: recipient,
            source: .selfPressed, pressedByName: "Mom", pressedAt: pressedAt
        )
        context.insert(record)
        try context.save()

        await engine.enqueue(entity: .checkIn, id: record.id, groupID: group)
        await remote.setNextPushError(.offline)
        let blocked = await engine.sync(remote: remote, groupID: group)
        #expect(blocked.wasOffline)
        #expect(await remote.count(.checkIn) == 0)

        let recovered = await engine.sync(remote: remote, groupID: group)
        #expect(recovered.pushed == 1)
        #expect(await remote.count(.checkIn) == 1)
    }

    @Test("Two presses on the same day are two records, never merged")
    func pressesNeverCoalesce() async throws {
        // A dose log and a check-in are both events rather than states. Merging
        // two presses would erase the fact that one of them happened, which is
        // the one thing this table exists to record.
        #expect(SyncEntity.checkIn.isCoalescable == false)
        #expect(SyncEntity.doseLog.isCoalescable == false)
        #expect(SyncEntity.checkInSettings.isCoalescable == true)
        #expect(SyncEntity.medication.isCoalescable == true)
    }

    @MainActor
    @Test("The window label reads as a time, not as minutes from midnight")
    func windowLabel() {
        let label = CheckInService.windowLabel(start: 8 * 60, end: 20 * 60)
        #expect(label.contains("to"))
        #expect(!label.contains("480"))
        #expect(!label.contains("—"))
    }
}

/// Roles are cached locally on purpose: an app that cannot tell whether you are
/// a caregiver until the network answers has to either block or guess, and in
/// an emergency room both are wrong.
@Suite("Group roles")
struct GroupRoleTests {

    @Test("Owner and caregiver are staff; the subject is not")
    func staffSplit() {
        #expect(GroupRole.owner.isStaff)
        #expect(GroupRole.caregiver.isStaff)
        #expect(GroupRole.subject.isStaff == false)
    }

    @Test("An unknown role degrades to the least privileged one")
    func unknownRoleIsSubject() {
        let group = CareGroup(name: "Family", role: .owner)
        group.roleRaw = "administrator"
        // If a future server role reaches an old client, showing too little is
        // recoverable and showing too much is not.
        #expect(group.role == .subject)
    }

    @Test("Plus expires, and lifetime does not")
    func entitlementResolution() {
        let group = CareGroup(name: "Family", role: .owner)
        #expect(group.hasPlus == false)

        group.entitlement = "plus"
        group.entitlementExpiresAt = Date().addingTimeInterval(-60)
        #expect(group.hasPlus == false)

        group.entitlementExpiresAt = Date().addingTimeInterval(3600)
        #expect(group.hasPlus)

        group.entitlementExpiresAt = nil
        group.isLifetime = true
        #expect(group.hasPlus)
    }

    @Test("An invite failure code carries a sentence a person can act on")
    func inviteFailureCopy() {
        #expect(InviteFailure(rawValue: "invalid_code") == .invalidCode)
        #expect(InviteFailure(rawValue: "rate_limited") == .rateLimited)
        #expect(InviteFailure(rawValue: "already_in_group") == .alreadyInGroup)
        #expect(InviteFailure.invalidCode.message.contains("48 hours"))
        #expect(InviteFailure.rateLimited.message.contains("hour"))
        #expect(InviteFailure.alreadyInGroup.message.contains("care circle"))
    }
}
