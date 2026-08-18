import Foundation
import Supabase
import Testing

@testable import Aging

/// The rule these tests protect: a caregiver standing in an emergency room with
/// no signal must keep their session and their cached medication list.
///
/// Getting this wrong in the safe direction shows a stale list, which someone
/// can work around. Getting it wrong in the unsafe direction logs them out and
/// hides Mom's allergies behind a sign-in screen at the moment they are being
/// asked for them out loud.
@MainActor
struct AuthOfflineTests {

    // MARK: - Transport failures are never a sign-out

    @Test("Losing the network keeps the session")
    func offlineIsNotSignedOut() {
        let cases: [URLError.Code] = [
            .notConnectedToInternet,
            .networkConnectionLost,
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dataNotAllowed,
            .internationalRoamingOff,
            .secureConnectionFailed
        ]

        for code in cases {
            #expect(
                AuthService.classify(URLError(code)) == .offline,
                "URLError.\(code) must be treated as offline, not as a sign-out"
            )
        }
    }

    @Test("An unrecognised error defaults to offline rather than signing the user out")
    func unknownErrorsFailSafe() {
        struct Mystery: Error {}
        #expect(AuthService.classify(Mystery()) == .offline)

        // A 5xx from the auth server is the backend having a bad day, not this
        // user's refresh token being revoked.
        let serverError = AuthError.api(
            message: "Internal Server Error",
            errorCode: .unexpectedFailure,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse()
        )
        #expect(AuthService.classify(serverError) == .offline)
    }

    @Test("Rate limiting is not a sign-out")
    func rateLimitIsNotSignedOut() {
        let error = AuthError.api(
            message: "Too many requests",
            errorCode: .overRequestRateLimit,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse()
        )
        #expect(AuthService.classify(error) == .offline)
    }

    // MARK: - Definitive rejections are a sign-out

    @Test("A server rejection of the refresh token signs the user out")
    func revokedTokenSignsOut() {
        let codes: [ErrorCode] = [
            .refreshTokenNotFound,
            .refreshTokenAlreadyUsed,
            .sessionNotFound,
            .sessionExpired,
            .userNotFound,
            .userBanned,
            .badJWT
        ]

        for code in codes {
            let error = AuthError.api(
                message: "rejected",
                errorCode: code,
                underlyingData: Data(),
                underlyingResponse: HTTPURLResponse()
            )
            #expect(
                AuthService.classify(error) == .revoked,
                "\(code) is the server definitively rejecting this session"
            )
        }
    }

    @Test("A missing session is a sign-out")
    func missingSessionSignsOut() {
        #expect(AuthService.classify(AuthError.sessionMissing) == .revoked)
    }

    // MARK: - Launch never blocks

    @Test("Bootstrap resolves synchronously and never lands on unknown")
    func bootstrapIsSynchronous() {
        let auth = AuthService.shared
        auth.bootstrap()

        // The specific outcome depends on whether a session is cached in this
        // environment. What matters is that a single synchronous call with no
        // network reaches a decision, because first paint depends on it.
        #expect(auth.state != .unknown)
    }
}
