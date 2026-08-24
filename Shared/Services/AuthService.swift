import AuthenticationServices
import CryptoKit
import Foundation
import OSLog
import Supabase

/// Session ownership, built around one requirement that outranks everything
/// else in this app: someone standing in an emergency room with no signal must
/// land in the app holding Mom's medication list, not on a sign-in screen.
///
/// Three things make that true, and all three are load-bearing:
///
/// 1. `bootstrap()` reads `client.auth.currentSession`, which is a synchronous,
///    non-throwing, network-free read of the Keychain-backed store. The async
///    `client.auth.session` property refreshes over the network and throws when
///    it cannot, which would put a login wall in front of a cached medication
///    list at the worst possible moment.
/// 2. The client is configured with `emitLocalSessionAsInitialSession: true`,
///    so the SDK emits the stored session immediately regardless of expiry and
///    swallows a failed background refresh rather than reporting a sign-out.
/// 3. `classify(_:)` never treats a transport failure as a sign-out. Only a
///    definitive server rejection of the refresh token counts.
///
/// Point 3 is not redundant with point 2. As of the version read while writing
/// this, `sessionManager.remove()` is reachable from exactly one place in the
/// SDK (`signOut()`), and a failed refresh only throws. But that behaviour has
/// regressed before, and a comment in the SDK already claims something its own
/// `SessionManager` no longer does. We own this guarantee, not the SDK.
@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    enum State: Equatable {
        /// Before the first `bootstrap()`. Never rendered as signed out.
        case unknown
        case signedOut
        case signedIn(userID: UUID)
    }

    private(set) var state: State = .unknown
    /// True when the last network attempt failed for transport reasons. Drives
    /// a quiet "showing your saved copy" banner, never a blocking screen.
    private(set) var isOffline = false
    private(set) var displayName: String = ""

    let client: SupabaseClient

    private let log = Logger(subsystem: "com.jackwallner.aging", category: "auth")
    private var currentNonce: String?

    var userID: UUID? {
        if case let .signedIn(id) = state { return id }
        return nil
    }

    var isSignedIn: Bool { userID != nil }

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                db: SupabaseClientOptions.DatabaseOptions(
                    // A `date` column decodes here too. See `PostgrestCoding`:
                    // the SDK's own strategy rejects one, and a rejected field
                    // fails the whole page rather than itself.
                    decoder: PostgrestCoding.decoder()
                ),
                auth: SupabaseClientOptions.AuthOptions(
                    // Emit the stored session on launch even if it has expired,
                    // and refresh in the background. Without this the SDK awaits
                    // a network refresh before reporting the initial session,
                    // which is the offline-launch failure this app cannot have.
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    // MARK: - Launch

    /// Synchronous, network-free. Safe to call before first paint.
    func bootstrap() {
        if let session = client.auth.currentSession {
            state = .signedIn(userID: session.user.id)
            displayName = Self.name(from: session.user)
            log.info("Restored a local session; expired: \(session.isExpired)")
        } else {
            state = .signedOut
            log.info("No local session")
        }
    }

    /// Best-effort refresh, run after the UI is already on screen. Failure here
    /// is expected and must never be escalated into a sign-out.
    func refreshInBackground() async {
        guard client.auth.currentSession != nil else { return }
        do {
            let session = try await client.auth.refreshSession()
            state = .signedIn(userID: session.user.id)
            displayName = Self.name(from: session.user)
            isOffline = false
        } catch {
            switch Self.classify(error) {
            case .offline:
                isOffline = true
                log.notice("Refresh failed, staying on the cached session: \(error.localizedDescription)")
            case .revoked:
                log.error("Refresh token was rejected by the server; signing out")
                await forgetSession()
            }
        }
    }

    // MARK: - Error classification

    enum Failure {
        /// Transport, DNS, timeout, airplane mode. Keep the session and the cache.
        case offline
        /// The server definitively rejected the refresh token. Genuinely signed out.
        case revoked
    }

    /// Deliberately conservative: anything not recognised as a definitive
    /// rejection is treated as offline. Wrongly staying signed in shows a stale
    /// medication list, which is recoverable. Wrongly signing out wipes access
    /// in an emergency, which is not.
    static func classify(_ error: Error) -> Failure {
        if error is URLError { return .offline }

        guard let authError = error as? AuthError else { return .offline }

        switch authError {
        case .sessionMissing:
            return .revoked
        default:
            break
        }

        switch authError.errorCode {
        case .refreshTokenNotFound, .refreshTokenAlreadyUsed,
             .sessionNotFound, .sessionExpired,
             .userNotFound, .userBanned, .badJWT:
            return .revoked
        default:
            return .offline
        }
    }

    // MARK: - Sign in

    /// Sign in with Apple remains the shortest path. Email codes are the
    /// fallback for people who do not use Apple sign-in or are opening a family
    /// invitation on a different Apple account.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = Self.sha256(nonce)
    }

    func completeAppleSignIn(_ authorization: ASAuthorization) async throws {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let nonce = currentNonce
        else {
            throw AuthServiceError.appleCredentialUnavailable
        }

        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        currentNonce = nil

        state = .signedIn(userID: session.user.id)
        isOffline = false

        // Apple only hands over the name on the very first authorization, so it
        // has to be captured now or never.
        let appleName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        if !appleName.isEmpty {
            try? await updateDisplayName(appleName)
        } else {
            displayName = Self.name(from: session.user)
        }
    }

    /// Reachable only when `AuthFeatures.emailSignInEnabled` is on.
    func requestEmailLink(_ email: String) async throws {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@") else { throw AuthServiceError.invalidEmail }
        try await client.auth.signInWithOTP(
            email: normalized,
            redirectTo: URL(string: "elderhub://auth")
        )
    }

    func completeEmailSignIn(url: URL, displayName name: String) async throws {
        let session = try await client.auth.session(from: url)

        state = .signedIn(userID: session.user.id)
        isOffline = false
        displayName = Self.name(from: session.user)

        // Non-fatal, exactly as in the Apple path. The session is already
        // established by this point, so letting a failed profile write throw
        // would report a successful sign-in as a failure and skip the work the
        // caller does afterwards (RevenueCat identify above all).
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            try? await updateDisplayName(trimmedName)
        }
    }

    // MARK: - Profile

    func updateDisplayName(_ name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let userID else { return }

        try await client
            .from("profiles")
            .update(["display_name": trimmed])
            .eq("id", value: userID)
            .execute()

        displayName = trimmed
    }

    // MARK: - Leaving

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            log.error("Sign out call failed, clearing locally anyway: \(error.localizedDescription)")
        }
        await forgetSession()
    }

    /// App Review 5.1.1(v). The RPC hands off or cleans up any group this user
    /// owns and unlinks them from any recipient row, but never deletes the
    /// family's medical history: rows they authored keep a name snapshot so the
    /// record still reads "logged by Sarah" after Sarah is gone.
    func deleteAccount() async throws {
        try await client.rpc("delete_account").execute()
        await forgetSession()
    }

    private func forgetSession() async {
        state = .signedOut
        displayName = ""
    }

    // MARK: - Helpers

    private static func name(from user: User) -> String {
        if let value = user.userMetadata["display_name"]?.stringValue, !value.isEmpty {
            return value
        }
        if let value = user.userMetadata["full_name"]?.stringValue, !value.isEmpty {
            return value
        }
        return ""
    }

    private static func randomNonceString(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status != errSecSuccess {
            // The nonce only needs to be unguessable per attempt; UUIDs are an
            // acceptable fallback if the security framework refuses.
            return UUID().uuidString + UUID().uuidString
        }
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Which sign-in methods the UI offers.
///
/// The email flow is finished and works, but the Supabase project has no custom
/// SMTP, so it runs on the built-in service: two auth emails per hour across the
/// entire project, not per account. That is not a fallback, it is a dead end for
/// the third person to try it in any given hour, and a 2.1 rejection if a
/// reviewer picks it. Sign in with Apple is therefore the only offered method,
/// which is what every build before this one shipped and is 4.8-clean on its own.
///
/// Turn this on once `smtp_host` is set on the project and
/// `rate_limit_email_sent` is raised. Nothing else has to change: the deep-link
/// handler stays wired, so a link already in someone's inbox still resolves.
enum AuthFeatures {
    static let emailSignInEnabled = false
}

enum AuthServiceError: LocalizedError {
    case appleCredentialUnavailable
    case invalidEmail

    var errorDescription: String? {
        switch self {
        case .appleCredentialUnavailable:
            return "Apple did not return a sign-in token. Please try again."
        case .invalidEmail:
            return "Enter a valid email address."
        }
    }
}
