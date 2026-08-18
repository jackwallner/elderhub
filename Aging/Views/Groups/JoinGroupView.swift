import SwiftUI

/// Entering the code the family read out over the phone.
///
/// The code alphabet excludes 0/O/1/I/L on the server for exactly that reason,
/// and this screen upper-cases and strips spaces on the way in, because someone
/// dictating "H, 7, K..." over a landline is the actual delivery mechanism.
struct JoinGroupView: View {
    let isOnboarding: Bool
    var initialCode: String = ""
    let onJoined: (GroupRole) -> Void

    @Environment(AuthService.self) private var auth
    @Environment(GroupService.self) private var groups
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var cleaned: String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// A tapped invitation link reaches this screen directly, from a phone that
    /// may never have signed in: an existing solo install has people and a
    /// finished onboarding flag, so it lands in the tabs and opens this sheet
    /// rather than going through the onboarding sign-in step. Without this the
    /// only thing here was a Join button that answered "Sign in first." and no
    /// way to do it.
    var body: some View {
        if auth.isSignedIn {
            codeEntry
        } else {
            SignInView(purpose: .joinFamily, onSignedIn: {})
                .navigationTitle(isOnboarding ? "" : "Join a Care Circle")
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var codeEntry: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "envelope.open")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                Text("Enter your code")
                    .font(.title2.bold())
                Text("Eight letters and numbers, from whoever invited you.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)

            TextField("ABCD2345", text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 28)

            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            Spacer()

            Button {
                Task { await join() }
            } label: {
                Text("Join")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(cleaned.count != 8 || isWorking)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .overlay {
            if isWorking { ProgressView().controlSize(.large) }
        }
        .navigationTitle(isOnboarding ? "" : "Join a Care Circle")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if code.isEmpty { code = initialCode }
        }
        // A second link tapped while this screen is up carries a different
        // code. Nothing has been typed yet in that case, so take it.
        .onChange(of: initialCode) { _, newCode in
            if !newCode.isEmpty { code = newCode }
        }
    }

    private func join() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            try await groups.acceptInvite(code: cleaned)
            await groups.loadMembers()
            onJoined(groups.role)
            if !isOnboarding { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
