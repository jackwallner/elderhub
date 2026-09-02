import StoreKit
import SwiftUI
import UIKit

/// What the reader did, so the host can act after the sheet closes.
enum ReviewPromptOutcome: Sendable {
    case notNow
    /// Said yes. The host raises Apple's own prompt, which may show nothing.
    case wantsToRate
    /// Said no and went to write to us instead.
    case sendingFeedback
}

/// The enjoyment gate: one question, then either the App Store or a way to tell
/// us what is wrong.
///
/// Asking everyone for a rating and sending them all to the App Store is how an
/// app collects its unhappy reviews in public. The fork is the point: a yes
/// goes to Apple's prompt, a no goes to an email that reaches somebody, and the
/// person who is annoyed gets a route that is not a one-star review.
struct ReviewPromptSheet: View {
    let onFinish: (ReviewPromptOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 46))
                        .foregroundStyle(.tint)
                        .padding(.top, 16)

                    Text("Is Elderhub helping?")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    // No claim about what the app does for anyone's health, and
                    // no flattery about how well the caregiving is going (I6).
                    // The reason given is the true one: almost nobody looking
                    // for an app like this knows it exists.
                    Text("Families find this app almost entirely through its ratings. If it has been useful, a rating takes a few seconds and genuinely helps somebody else find it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)

                    VStack(spacing: 10) {
                        Button {
                            onFinish(.wantsToRate)
                            dismiss()
                        } label: {
                            Text("Rate Elderhub")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("review.rate")

                        Button {
                            onFinish(.sendingFeedback)
                            dismiss()
                        } label: {
                            Text("Something's not right")
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("review.feedback")
                    }
                    .padding(.horizontal, 4)
                }
                .padding(24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        onFinish(.notNow)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Getting a useful bug report out of a caregiver without asking them to
/// describe their setup.
///
/// The support link in Settings went to a web page, which is the wrong shape
/// for the person holding the phone at the moment something is wrong, and it
/// arrives carrying none of what would let anyone diagnose it. This prefills
/// the version, build, iOS, how many people are on the record and whether sync
/// is working. It deliberately carries no names, no medications and nothing
/// else from the record (I5): a support email is not a place for somebody
/// else's health information.
@MainActor
enum SupportMail {
    /// The alias every published page already uses. It reads as the old name
    /// because it predates the Elderhub rename, and it is deliberately not
    /// "corrected" here: the privacy, terms, support and join pages, and the
    /// live App Store listing, all point at this one, so mail from the app has
    /// to land in the same place as mail from the site. Changing it is a job
    /// for all of those at once, not for this file alone.
    static let address = "jackwallner+medlist@gmail.com"

    static func url(personCount: Int, isSignedIn: Bool, lastSyncedAt: Date?) -> URL? {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current.systemVersion

        let sync: String
        if !isSignedIn {
            sync = "not signed in (local only)"
        } else if let lastSyncedAt {
            sync = "last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))"
        } else {
            sync = "signed in, never synced"
        }

        let body = """


        ---
        The lines below help us find the problem. Please leave them in.
        Elderhub \(version) (\(build))
        iOS \(device)
        Care records on this phone: \(personCount)
        Sync: \(sync)
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Elderhub feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
