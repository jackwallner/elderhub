import Foundation
import Testing

@testable import Aging

/// The invitation is the one part of this app that leaves the phone as text and
/// is read by someone who has never seen the app. Everything that can go wrong
/// with it goes wrong silently: a link a desktop mail client will not draw, an
/// address mangled by a `+`, a code the server refuses after the UI accepted it.
struct InviteLinkTests {
    // MARK: Codes

    @Test func normalizesDictatedCodes() {
        #expect(InviteLink.normalized("abcd2345") == "ABCD2345")
        #expect(InviteLink.normalized("ABCD-2345") == "ABCD2345")
        #expect(InviteLink.normalized(" abcd 2345 ") == "ABCD2345")
    }

    @Test func rejectsWrongLengthCodes() {
        #expect(InviteLink.normalized("ABCD234") == nil)
        #expect(InviteLink.normalized("ABCD23456") == nil)
        #expect(InviteLink.normalized("") == nil)
    }

    // MARK: Links

    @Test func readsCodeFromTheAppScheme() throws {
        let url = try #require(URL(string: "elderhub://invite?code=ABCD2345"))
        #expect(InviteLink.code(from: url) == "ABCD2345")
    }

    @Test func readsCodeFromTheWebLinkInTheMessage() throws {
        // Exactly the address the email carries, so a change to `webURL` that
        // the parser cannot read back is caught here rather than by a relative.
        let url = try #require(InviteLink.webURL(code: "ABCD2345"))
        #expect(InviteLink.code(from: url) == "ABCD2345")
    }

    @Test func ignoresOtherLinks() throws {
        let auth = try #require(URL(string: "elderhub://auth#access_token=x"))
        #expect(InviteLink.code(from: auth) == nil)

        let site = try #require(URL(string: "https://jackwallner.com/ios/elderhub/"))
        #expect(InviteLink.code(from: site) == nil)

        let short = try #require(URL(string: "elderhub://invite?code=ABC"))
        #expect(InviteLink.code(from: short) == nil)
    }

    // MARK: Email addresses

    @Test func emailValidationMatchesTheServerCheck() {
        // `invite_email_is_normalized`, migration 0015.
        #expect(InviteLink.isValidEmail("someone@example.com"))
        #expect(InviteLink.isValidEmail("jack+care@gmail.com"))
        // The old client check was "contains @ and .", which let these through
        // to a raw 22023 from Postgres.
        #expect(!InviteLink.isValidEmail("someone@example."))
        #expect(!InviteLink.isValidEmail("someone.example@"))
        #expect(!InviteLink.isValidEmail("some one@example.com"))
        #expect(!InviteLink.isValidEmail(""))
    }

    // MARK: The message

    @Test func messageLeadsWithAnAddressAnyMailClientCanOpen() {
        let text = InviteMessage.text(code: "ABCD2345", role: .caregiver, personName: nil)
        #expect(text.contains("https://jackwallner.com/ios/elderhub/join.html?code=ABCD2345"))
        #expect(text.contains("ABCD2345"))
        // A custom scheme is unopenable on a phone without the app and is not
        // drawn as a link at all by a desktop client, so it must not be the
        // thing the message asks someone to tap.
        #expect(!text.contains("elderhub://"))
    }

    @Test func subjectMessageNamesTheRecordTheyAreJoining() {
        let text = InviteMessage.text(code: "ABCD2345", role: .subject, personName: "Mom")
        #expect(text.contains("Mom"))
        #expect(text.contains("only that record"))
    }

    @Test func mailtoEscapesTheAddressAndTheBody() throws {
        let url = try #require(
            InviteMessage.emailURL(
                address: "jack+care@gmail.com",
                code: "ABCD2345",
                role: .caregiver,
                personName: nil
            )
        )
        let string = url.absoluteString
        // A bare `+` in a mailto is read as a space by some clients, and a bare
        // `?` in the body would truncate everything after it.
        #expect(string.hasPrefix("mailto:jack%2Bcare%40gmail.com?subject="))
        #expect(string.contains("&body="))
        #expect(!string.dropFirst("mailto:jack%2Bcare%40gmail.com?".count).contains("?"))

        let body = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "body" })?.value
        )
        #expect(body.contains("join.html?code=ABCD2345"))
    }

    @Test func mailtoRefusesAnAddressTheServerWouldReject() {
        #expect(
            InviteMessage.emailURL(
                address: "not-an-address",
                code: "ABCD2345",
                role: .caregiver,
                personName: nil
            ) == nil
        )
    }
}
