import SwiftUI

/// Single question, because the fastest path to value is one person and one med.
/// Everything else can be added later.
struct OnboardingView: View {
    var isSolo: Bool = false
    var requiresAttestation: Bool = false
    let onComplete: (String, String, Bool) -> Void

    @State private var name = ""
    @State private var relationship = ""
    @State private var hasPermission = false

    /// One-tap fills for the common cases, not the set of allowed answers. The
    /// people this app is used for are as often an aunt, a neighbour or a
    /// friend, and a fixed list of four told those users the app was not for
    /// them on the first screen. The field below takes anything, including
    /// nothing: `Person.relationship` has always been free text that defaults
    /// to empty, and `displayLabel` reads the entered name regardless, so a
    /// blank relationship is a complete record rather than a half-filled one.
    private var suggestions: [String] {
        isSolo ? ["Me"] : ["Mom", "Dad", "Spouse", "Partner", "Me"]
    }

    private var trimmedRelationship: String {
        relationship.trimmingCharacters(in: .whitespaces)
    }

    /// Case- and space-insensitive, so a chip stays lit when the same word was
    /// typed rather than tapped.
    private func isChosen(_ option: String) -> Bool {
        trimmedRelationship.caseInsensitiveCompare(option) == .orderedSame
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "list.clipboard")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)

                Text(isSolo ? "What should we call you?" : "Who are you keeping track of?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(isSolo
                     ? "Your own list. You can add someone else later."
                     : "Start with one person. You can add more later.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                TextField(isSolo ? "Your name" : "Their name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .textContentType(.name)

                TextField("Relationship (optional)", text: $relationship)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("onboarding.relationship")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(suggestions, id: \.self) { option in
                            Button {
                                // Tapping the lit chip clears it, so "none of
                                // these" is reachable without deleting text.
                                relationship = isChosen(option) ? "" : option
                            } label: {
                                Text(option)
                                    .font(.callout.weight(.medium))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .background(
                                        Capsule().fill(
                                            isChosen(option)
                                                ? Color.accentColor.opacity(0.18)
                                                : Color.secondary.opacity(0.12)
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isChosen(option) ? [.isSelected] : [])
                        }
                    }
                    .padding(.horizontal, 2)
                }

                if requiresAttestation {
                    Toggle(isOn: $hasPermission) {
                        Text("I have permission to keep and share this person’s care information.")
                            .font(.subheadline)
                    }
                    .toggleStyle(.switch)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 28)

            Spacer()

            // Footer space is reserved whether or not the button is enabled, so the
            // layout never shifts under the user's thumb.
            VStack(spacing: 10) {
                Button {
                    onComplete(
                        name.trimmingCharacters(in: .whitespaces),
                        trimmedRelationship,
                        hasPermission
                    )
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    name.trimmingCharacters(in: .whitespaces).isEmpty
                    || (requiresAttestation && !hasPermission)
                )

                // Reserved footer space either way, so the layout never shifts
                // under the user's thumb as the button enables.
                Text("A copy stays on this phone, so it opens with no signal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .onAppear {
            if isSolo { relationship = "Me" }
        }
    }
}

#Preview {
    OnboardingView { _, _, _ in }
}
