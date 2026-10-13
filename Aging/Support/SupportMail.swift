import Foundation
import UIKit

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
