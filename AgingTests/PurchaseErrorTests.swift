import Foundation
import Testing

@testable import Aging

/// Ask to Buy reads as waiting for a parent, not as a failure, and a lost
/// connection reads as the app's own line instead of RevenueCat's English.
///
/// Codes are RevenueCat's `ErrorCode` raw values (`paymentPendingError` 20,
/// `networkError` 10, `offlineConnectionError` 35, `purchaseNotAllowedError`
/// 3), thrown the way the SDK throws them: as an `NSError` in its domain.
struct PurchaseErrorTests {
    private func rc(_ code: Int) -> Error { PurchaseError.revenueCatError(code: code) }

    @Test func aPendingPaymentIsWaitingForApproval() {
        let shown = PurchaseError.shown(rc(20))
        #expect(shown as? PurchaseError == .waitingForApproval)
        #expect((shown as? PurchaseError)?.isPending == true)
    }

    @Test func theWaitingCopyIsCalmAndSaysWhatHappensNext() {
        #expect(
            PurchaseError.waitingForApproval.localizedDescription
                == "Waiting for approval. Your purchase unlocks once it is approved."
        )
    }

    @Test func networkAndOfflineErrorsReadAsTheStoreUnreachableLine() {
        for code in [10, 35] {
            let shown = PurchaseError.shown(rc(code))
            #expect(shown as? PurchaseError == .storeUnreachable)
            #expect((shown as? PurchaseError)?.isPending == false)
        }
        #expect(PurchaseError.storeUnreachable.localizedDescription == "We couldn't reach the App Store just now.")
    }

    @Test func otherErrorsPassThroughUnchanged() {
        let notAllowed = PurchaseError.shown(rc(3)) as NSError
        #expect(notAllowed.domain == PurchaseError.revenueCatErrorDomain)
        #expect(notAllowed.code == 3)

        // The same number in another domain is not RevenueCat's pending error.
        let unrelated = PurchaseError.shown(NSError(domain: "SomethingElse", code: 20)) as NSError
        #expect(unrelated.domain == "SomethingElse")
        #expect(unrelated.code == 20)
    }
}
