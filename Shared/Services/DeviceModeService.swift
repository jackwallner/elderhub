import CryptoKit
import Foundation
import Observation

/// Who is holding *this phone*, and whether they are allowed to change things.
///
/// This is deliberately a different axis from `GroupRole`. A role is an
/// agreement between accounts, enforced by RLS on the server, and changing it
/// needs the circle's organizer. Whose hands the phone is in right now is a
/// local fact about one device, it changes several times a day in real
/// households ("here Mom, press this"), and no server has any business
/// arbitrating it.
///
/// So there are two things and they are named differently everywhere:
///
/// - `GroupRole` .owner / .caregiver / .subject: what this *account* may read
///   and write in the family circle.
/// - `DeviceMode` .caregiver / .recipient: what the person currently holding
///   *this handset* sees.
///
/// Handing the phone over swaps the app to the recipient's screen: one big
/// check-in button, their own medication list, the emergency card, and no way
/// to edit the record. A caregiver PIN is what swaps it back. The PIN protects
/// against a confused tap, not against an adversary: this is a family, and the
/// data it guards is already readable on the same screen by design.
///
/// Two things this must never do, both structural (see CLAUDE.md):
/// - never consult `StoreService`, at any depth. Check-in has no paywall.
/// - never gate the emergency card. Recipient mode still shows it, because the
///   whole point of the card is the moment nobody can remember a passcode.
@MainActor
@Observable
final class DeviceModeService {
    static let shared = DeviceModeService()

    enum Mode: String, CaseIterable, Sendable {
        /// Someone looking after another person. The full app.
        case caregiver
        /// The person being looked after, holding the phone themselves.
        case recipient

        var label: String {
            switch self {
            case .caregiver: return "Me, helping someone"
            case .recipient: return "The person being cared for"
            }
        }

        var detail: String {
            switch self {
            case .caregiver:
                return "The full record: medications, tasks, bills, visits and sharing."
            case .recipient:
                return "One big check-in button, their medications and the emergency card. Nothing can be edited."
            }
        }

        var symbol: String {
            switch self {
            case .caregiver: return "person.badge.shield.checkmark"
            case .recipient: return "hand.wave"
            }
        }
    }

    private enum Key {
        static let mode = "deviceMode"
        static let pinHash = "caregiverPINHash"
        static let pinSalt = "caregiverPINSalt"
        static let handedOverPerson = "handoverPersonID"
    }

    /// Four digits. Long enough to be deliberate, short enough for someone to
    /// key in one-handed in a hallway.
    static let pinLength = 4

    private let defaults: UserDefaults

    private(set) var mode: Mode
    private(set) var hasPIN: Bool

    /// Whose screen recipient mode is showing, chosen at the moment of handing
    /// the phone over.
    ///
    /// Without this the check-in screen had to guess, and its guess was the
    /// account's own linked row and then simply the first person in the store.
    /// In the household this app is for, two recipients is the ordinary case
    /// (both parents), and a guess there hands Dad the phone showing Mom's
    /// medications and logs her check-in when he presses the button. Wrong
    /// person is worse than no person.
    ///
    /// Nil is a valid, non-broken state: a handset that has only ever had one
    /// record, or one handed over by a build that predates this, falls back to
    /// the old resolution rather than showing nothing.
    private(set) var handedOverPersonID: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.mode = Mode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .caregiver
        self.hasPIN = defaults.data(forKey: Key.pinHash) != nil
        self.handedOverPersonID = defaults.string(forKey: Key.handedOverPerson).flatMap(UUID.init(uuidString:))
    }

    var isRecipientMode: Bool { mode == .recipient }

    /// Whether the record may be edited on this handset right now.
    ///
    /// Read by every editing affordance rather than by a blanket `.disabled()`
    /// on the root: a disabled screen is unreadable, and reading is the thing
    /// recipient mode is *for*.
    var allowsEditing: Bool { mode == .caregiver }

    // MARK: - Switching

    /// Hands the phone to the person being looked after.
    ///
    /// Never asks for the PIN: giving up access needs no permission. Coming
    /// back does.
    ///
    /// - Parameter personID: whose screen to show. Pass nil only when the
    ///   handset has nobody to choose between; see `handedOverPersonID`.
    func handOver(to personID: UUID? = nil) {
        handedOverPersonID = personID
        if let personID {
            defaults.set(personID.uuidString, forKey: Key.handedOverPerson)
        } else {
            defaults.removeObject(forKey: Key.handedOverPerson)
        }
        set(.recipient)
    }

    /// Comes back to the caregiver's app.
    ///
    /// - Returns: false when a PIN is set and the one supplied is wrong, which
    ///   is the only case that refuses. With no PIN set this always succeeds,
    ///   and the settings screen says so plainly rather than pretending the
    ///   handset is locked.
    @discardableResult
    func returnToCaregiver(pin: String?) -> Bool {
        guard hasPIN else {
            set(.caregiver)
            return true
        }
        guard let pin, verify(pin: pin) else { return false }
        set(.caregiver)
        return true
    }

    private func set(_ newMode: Mode) {
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Key.mode)
        // Coming back to the caregiver ends that handover. Keeping the id would
        // make the next "hand the phone over" silently reuse whoever held it
        // last, which is the same wrong-person bug by a slower route.
        if newMode == .caregiver {
            handedOverPersonID = nil
            defaults.removeObject(forKey: Key.handedOverPerson)
        }
    }

    // MARK: - The PIN

    /// - Returns: false when the PIN is not exactly `pinLength` digits.
    @discardableResult
    func setPIN(_ pin: String) -> Bool {
        guard Self.isWellFormed(pin) else { return false }
        var salt = Data(count: 16)
        salt.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            for offset in 0..<buffer.count {
                base.storeBytes(of: UInt8.random(in: 0...255), toByteOffset: offset, as: UInt8.self)
            }
        }
        defaults.set(salt, forKey: Key.pinSalt)
        defaults.set(Self.digest(pin: pin, salt: salt), forKey: Key.pinHash)
        hasPIN = true
        return true
    }

    /// Clearing the PIN also comes back to the caregiver's app: leaving a phone
    /// in recipient mode with nothing to unlock it is a door with no handle.
    func clearPIN() {
        defaults.removeObject(forKey: Key.pinHash)
        defaults.removeObject(forKey: Key.pinSalt)
        hasPIN = false
        set(.caregiver)
    }

    func verify(pin: String) -> Bool {
        guard
            let stored = defaults.data(forKey: Key.pinHash),
            let salt = defaults.data(forKey: Key.pinSalt)
        else { return false }
        // Constant time is theatre against someone who can already read the
        // defaults, but it costs one line and the alternative is explaining
        // why it is missing.
        let candidate = Self.digest(pin: pin, salt: salt)
        guard candidate.count == stored.count else { return false }
        var difference: UInt8 = 0
        for (lhs, rhs) in zip(candidate, stored) { difference |= lhs ^ rhs }
        return difference == 0
    }

    static func isWellFormed(_ pin: String) -> Bool {
        pin.count == pinLength && pin.allSatisfy(\.isNumber)
    }

    private static func digest(pin: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(pin.utf8))
        return Data(SHA256.hash(data: input))
    }
}
