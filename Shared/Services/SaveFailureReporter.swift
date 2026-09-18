import Foundation
import Observation
import SwiftData
import os

/// Surfaces a local save that did not land. Without it a failed write looks
/// exactly like a successful one: a dose shows as logged, and is gone after the
/// app is closed. For someone else's medication record that is the worst kind
/// of silent failure this app has.
@MainActor
@Observable
final class SaveFailureReporter {
    static let shared = SaveFailureReporter()

    /// The last write that failed, phrased for a person. Nil while the store is fine.
    var message: String?

    private let logger = Logger(subsystem: "com.jackwallner.aging", category: "store")

    private init() {}

    /// Deliberately does not name the record: an alert can be screenshotted
    /// into a support email, and a person's medication has no business in it.
    func report(_ error: Error) {
        logger.error("Local save failed: \(String(describing: error), privacy: .private)")
        message = "Your last change could not be saved on this iPhone, so it may be missing after you close the app. This is usually because storage is full. Free up some space, then check the record and make the change again."
    }
}

extension ModelContext {
    /// Saves, or reports the failure. Does not roll back: call sites chain
    /// several changes on one context, and rolling back mid-chain would detach
    /// rows the next line still touches. The unsaved change stays pending and
    /// lands with the next save that succeeds.
    @MainActor
    @discardableResult
    func saveOrReport() -> Bool {
        do {
            try save()
            return true
        } catch {
            SaveFailureReporter.shared.report(error)
            return false
        }
    }
}
