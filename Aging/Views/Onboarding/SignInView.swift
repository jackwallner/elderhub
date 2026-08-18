import AuthenticationServices
import SwiftUI

/// Sign in with Apple first, with a password-free email link as the fallback.
struct SignInView: View {
    enum Purpose {
        case createFamily
        case joinFamily
        case backUp

        var headline: String {
            switch self {
            case .createFamily: return "Create your care circle"
            case .joinFamily: return "Join the care circle"
            case .backUp: return "Keep your list safe"
            }
        }

        var detail: String {
            switch self {
            case .createFamily:
                return "An account is what lets the rest of the family see the same list you do."
            case .joinFamily:
                return "After signing in, the invitation link or code connects you to the right care circle."
            case .backUp:
                return "Your list is backed up and comes back if you lose your phone. Nobody else is added."
            }
        }
    }

    let purpose: Purpose
    let onSignedIn: () -> Void
    /// Offered on every path except joining a family, which structurally needs
    /// an account. See the note on `skipButton`.
    var onSkip: (() -> Void)?

    @Environment(AuthService.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var usesEmail = false
    @State private var email = ""
    @AppStorage("pendingEmailDisplayName") private var name = ""
    @State private var linkWasSent = false

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "person.badge.shield.checkmark")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                Text(purpose.headline)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(purpose.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 14) {
                if usesEmail {
                    emailFields
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        auth.prepareAppleRequest(request)
                    } onCompletion: { result in
                        handle(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 52)
                    .disabled(isWorking)

                    if AuthFeatures.emailSignInEnabled {
                        Button("Use email instead") {
                            errorMessage = nil
                            usesEmail = true
                        }
                        .font(.body.weight(.medium))
                        .frame(minHeight: 44)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                skipButton

                Text("No password. Your saved care record still opens with no signal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .overlay {
            if isWorking { ProgressView().controlSize(.large) }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { onSignedIn() }
        }
    }

    @ViewBuilder
    private var emailFields: some View {
        if linkWasSent {
            Image(systemName: "envelope.badge")
                .font(.title)
                .foregroundStyle(.tint)

            Text("We sent a sign-in link to \(email.trimmingCharacters(in: .whitespacesAndNewlines)).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Open the email and tap the sign-in button. Elderhub will return here automatically.")
                .font(.body)
                .multilineTextAlignment(.center)

            Button("Open Mail") {
                if let url = URL(string: "message://") { openURL(url) }
            }
            .buttonStyle(.borderedProminent)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)

            HStack(spacing: 18) {
                Button("Send a new link") {
                    Task { await sendEmailLink() }
                }
                Button("Change email") {
                    linkWasSent = false
                }
            }
            .font(.subheadline)
            .frame(minHeight: 44)
        } else {
            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)

            TextField("Email address", text: $email)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("Email me a sign-in link") {
                Task { await sendEmailLink() }
            }
            .buttonStyle(.borderedProminent)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .disabled(
                !email.contains("@")
                || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || isWorking
            )

            Button("Use Apple instead") {
                errorMessage = nil
                usesEmail = false
            }
            .font(.subheadline)
            .frame(minHeight: 44)
        }
    }

    /// Skippable everywhere except the join-a-family path.
    ///
    /// This softens D2 ("account required to use the app") deliberately. I3 says
    /// a solo caregiver who never invites anyone gets the whole med tracker, and
    /// §11 says local data stays local-only until someone opts into an account.
    /// A hard sign-in wall in front of the medication list contradicts both, and
    /// puts a login screen between a first-time user and the only thing they
    /// came for. Sharing is what needs the account, so sharing is where the
    /// account is asked for; the Sharing tab offers it again at the moment it
    /// actually buys something.
    @ViewBuilder
    private var skipButton: some View {
        if let onSkip {
            Button("Not now") { onSkip() }
                .font(.subheadline)
                .padding(.top, 2)
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            // A cancel is not a failure worth shouting about.
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            errorMessage = error.localizedDescription

        case .success(let authorization):
            isWorking = true
            Task {
                defer { isWorking = false }
                do {
                    try await auth.completeAppleSignIn(authorization)
                    // The RevenueCat customer has to carry the Supabase user id
                    // before any purchase, or the webhook has no group to credit.
                    await StoreService.shared.identify()
                    await NotificationService.shared.registerIfAuthorized()
                    onSignedIn()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func sendEmailLink() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            try await auth.requestEmailLink(email)
            linkWasSent = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}
