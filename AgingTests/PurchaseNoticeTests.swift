import Foundation
import RevenueCat
import Testing

@testable import Aging

/// Ask to Buy reads as waiting, not as a failure, and a lost connection reads
/// as the paywall's own App Store line rather than RevenueCat's English.
struct PurchaseNoticeTests {
    @Test func askToBuyIsWaitingForApproval() {
        let notice = PurchaseNotice.from(RevenueCat.ErrorCode.paymentPendingError)
        #expect(notice == .waitingForApproval)
        #expect(!notice.isError)
        #expect(notice.message == "Waiting for approval. Your purchase unlocks once it is approved.")
    }

    @Test func noConnectionIsTheAppStoreLine() {
        let expected = "We couldn't reach the App Store just now. Check your connection and try again."
        for error: Error in [
            RevenueCat.ErrorCode.networkError,
            RevenueCat.ErrorCode.offlineConnectionError,
            URLError(.notConnectedToInternet),
        ] {
            let notice = PurchaseNotice.from(error)
            #expect(notice == .storeUnreachable)
            #expect(notice.isError)
            #expect(notice.message == expected)
        }
    }

    @Test func otherErrorsKeepTheStoreWords() {
        let error = RevenueCat.ErrorCode.purchaseNotAllowedError
        let notice = PurchaseNotice.from(error)
        #expect(notice == .failed(error.localizedDescription))
        #expect(notice.isError)
        #expect(notice.message == error.localizedDescription)
    }
}
