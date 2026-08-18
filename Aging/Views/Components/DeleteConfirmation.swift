import SwiftUI

/// A delete that has been asked for but not yet done.
///
/// Swipe-to-delete is the standard iOS gesture and it is fine for a row you can
/// retype. It is not fine for the rows in this app: a medication carries its
/// dose history, a vital reading is one point in the only longitudinal record
/// the family has, and the delete is a tombstone that propagates to everyone
/// else's phone. Person and emergency-contact deletion already asked; the rest
/// removed a health record on one horizontal gesture with no confirmation and
/// no undo, which meant the most common way to hit it was aiming at the tap
/// target that opens the editor.
struct PendingRecordDeletion: Identifiable {
    let id = UUID()
    /// "Delete this reading?" Named after the thing, not after the verb.
    let title: String
    /// What goes with it, and how far the delete travels.
    let message: String
    let confirmLabel: String
    let perform: () -> Void

    /// Builds the message so every screen says the same thing about scope. The
    /// shared clause only appears when the record really is shared: telling a
    /// solo user their delete reaches "everyone in the care circle" is noise.
    static func message(_ detail: String, isShared: Bool) -> String {
        isShared
            ? "\(detail) This removes it for everyone in your care circle."
            : detail
    }
}

extension View {
    /// The one confirmation dialog every health-record list uses.
    func recordDeletionConfirmation(_ pending: Binding<PendingRecordDeletion?>) -> some View {
        confirmationDialog(
            pending.wrappedValue?.title ?? "Delete this?",
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(pending.wrappedValue?.confirmLabel ?? "Delete", role: .destructive) {
                pending.wrappedValue?.perform()
                pending.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) { pending.wrappedValue = nil }
        } message: {
            Text(pending.wrappedValue?.message ?? "")
        }
    }
}
