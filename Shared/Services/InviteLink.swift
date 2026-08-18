import Foundation

/// One place for the shape of an invitation: what a code looks like, what link
/// carries it, what the message around it says, and how a link is read back.
///
/// The message used to lead with `elderhub://invite?code=...`. That address is
/// only meaningful on a phone that already has the app: Mail on a phone without
/// it offers "Safari cannot open the page", and a desktop client will not even
/// draw it as a link, so the person most likely to be invited (the one who has
/// never installed anything) is handed the one address that cannot help them.
/// Every message therefore carries an https address, and the custom scheme is
/// reached from that page by a tap.
enum InviteLink {
    /// Codes are eight characters from an alphabet that already excludes
    /// look-alikes (`random_invite_code`, migration 0004), because reading one
    /// out over the phone is the realistic delivery mechanism.
    static let codeLength = 8

    /// Canonical, and mirrored from the `elderhub` repo's `/docs`. See the
    /// hosting note in CLAUDE.md before changing it: this string ends up in
    /// mail that outlives the build that sent it.
    static let webBase = "https://jackwallner.com/ios/elderhub/join.html"

    static let downloadPage = "https://jackwallner.com/ios/elderhub/"

    /// Upper-cases and drops anything that is not a letter or a number, so a
    /// code dictated as "H, 7, K" and typed with spaces or dashes still lands.
    /// Returns nil unless what is left is exactly a code.
    static func normalized(_ raw: String) -> String? {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        return cleaned.count == codeLength ? cleaned : nil
    }

    static func webURL(code: String) -> URL? {
        URL(string: "\(webBase)?code=\(code)")
    }

    static func appURL(code: String) -> URL? {
        URL(string: "elderhub://invite?code=\(code)")
    }

    /// Reads a code back out of either address. The https form is here so that
    /// adding an associated domain later needs no second parser, and so the
    /// same function can be tested against the exact string the mail contains.
    static func code(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let carriesCode: Bool
        switch url.scheme?.lowercased() {
        case "elderhub":
            carriesCode = url.host?.lowercased() == "invite"
        case "https", "http":
            carriesCode = url.path.hasSuffix("/join.html")
        default:
            carriesCode = false
        }
        guard carriesCode else { return nil }
        guard let raw = components?.queryItems?.first(where: { $0.name == "code" })?.value else {
            return nil
        }
        return normalized(raw)
    }

    /// The server's own check, so a client-side "looks fine" and a server-side
    /// 22023 cannot disagree (`invite_email_is_normalized`, migration 0015).
    static func isValidEmail(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(
            of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$",
            options: [.regularExpression]
        ) != nil
    }
}

enum InviteMessage {
    static func text(code: String, role: GroupRole, personName: String?) -> String {
        let access = role == .subject
            ? "This invitation links you to \(personName ?? "your") care record. You will see only that record."
            : "As a helper, you will be able to see and update everyone in this care circle."
        let link = InviteLink.webURL(code: code)?.absoluteString ?? InviteLink.downloadPage
        return """
        You are invited to a care circle in Elderhub.

        \(access)

        Your invitation code is \(code)

        Open this link on your iPhone to join:
        \(link)

        That page shows the code and opens Elderhub for you. If you already have \
        the app, choose "I have an invitation" on the first screen and type the code in.

        The invitation works once and expires after 48 hours.
        """
    }

    /// Built by hand rather than with `URLComponents.queryItems`, which leaves
    /// `?`, `&`, `+` and `/` unescaped in a query value. The body contains a URL
    /// with its own query string and the address may contain a `+` tag, and a
    /// mail client is entitled to read either as a delimiter.
    static func emailURL(
        address: String,
        code: String,
        role: GroupRole,
        personName: String?
    ) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard InviteLink.isValidEmail(trimmed) else { return nil }
        guard
            let to = escape(trimmed),
            let subject = escape("Invitation to join Elderhub"),
            let body = escape(text(code: code, role: role, personName: personName))
        else { return nil }
        return URL(string: "mailto:\(to)?subject=\(subject)&body=\(body)")
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func escape(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: unreserved)
    }
}
