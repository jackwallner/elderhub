import XCTest

/// The test `architecture.md` §6 calls the one that must never be allowed to go
/// red, and which had never actually been written.
///
/// Invariant I1 is the whole reason this app exists: someone standing in an
/// emergency room with no signal opens it and is holding the medication list,
/// not a spinner and not a sign-in screen. Nothing guarded that. A change that
/// put a single `await` in front of first paint would have shipped unnoticed,
/// because every other test runs with a working network and a warm process.
///
/// "No network" is faked by pointing the app at an unroutable host
/// (`SupabaseConfig` lets DEBUG builds take the URL from the environment), which
/// is what airplane mode looks like from inside the process and is the only way
/// to get it on a headless simulator. The launch is genuinely cold: the app is
/// terminated first, and the assertions run against data that was already on
/// disk before the network went away.
@MainActor
final class OfflineLaunchUITests: XCTestCase {

    /// Unroutable on purpose. Port 1 on loopback refuses immediately, so the
    /// test fails fast on a regression rather than passing because a timeout
    /// happened to outlast the assertion.
    private let deadHost = "https://127.0.0.1:1"

    override func setUp() {
        continueAfterFailure = false
    }

    func testColdLaunchWithNoNetworkRendersTheEmergencyCardFromLocalData() {
        let app = XCUIApplication()

        // First launch, network as usual: get a real person onto the disk.
        app.launchArguments += ["-uitest-reset", "YES"]
        app.launch()
        let name = completeOnboarding(app)
        let seededCard = app.buttons["today.emergency-card"]
        scrollUntilHittable(seededCard, in: app)
        XCTAssertTrue(seededCard.waitForExistence(timeout: 10))

        // Now take the network away and cold launch. No reset argument, so the
        // store and the onboarding flag both survive, which is the real
        // scenario: an install that has been in use for weeks.
        app.terminate()
        app.launchArguments = []
        app.launchEnvironment["SUPABASE_URL"] = deadHost
        app.launch()

        // No login wall. `AuthService.bootstrap` reads the Keychain-backed
        // session synchronously and a failed background refresh is never a
        // sign-out, so a dead network must not push anyone back to onboarding.
        XCTAssertFalse(
            app.buttons["Start a care record"].waitForExistence(timeout: 3),
            "A cold launch with no network dropped back into onboarding"
        )
        XCTAssertFalse(
            app.buttons["Sign in with Apple"].exists,
            "A cold launch with no network put a sign-in wall in front of the medication list"
        )

        // First paint, from the local store, with the network refusing every
        // connection. The timeout is deliberately short: this render owes
        // nothing to any server, so anything slow enough to need longer means
        // something started awaiting the network before first paint.
        //
        // Asserted on the action row rather than on the emergency card, which
        // is further down the screen. Reaching the card needs hit-testing and
        // swipes, and both wait for the app to go idle: on a cold launch into
        // a refusing host that wait is the thing under test, so putting it in
        // front of the first assertion turned a fast render into a hang.
        XCTAssertTrue(
            app.buttons["today.quick.medications"].waitForExistence(timeout: 8),
            "The Today tab did not render offline"
        )

        // Then the payoff screen itself, once the app has settled.
        let card = app.buttons["today.emergency-card"]
        scrollUntilHittable(card, in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()
        XCTAssertTrue(app.navigationBars["Emergency Card"].waitForExistence(timeout: 5))

        // Rendered, and rendered with the real person on it. An empty card that
        // merely appeared would pass the check above and fail the user.
        let heading = app.staticTexts["emergency-card.name"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, name)
    }

    /// Returns the name the card is expected to carry. If a previous test in
    /// this bundle already seeded a person, onboarding does not appear and the
    /// existing name is read off the card instead of assumed.
    private func completeOnboarding(_ app: XCUIApplication) -> String {
        let supporter = app.buttons["Start a care record"]
        guard supporter.waitForExistence(timeout: 5) else {
            return existingPersonName(app)
        }
        supporter.tap()

        // The name is asked before the account, not after it (App Review 4.0).
        let nameField = app.textFields["Their name"]
        guard nameField.waitForExistence(timeout: 5) else {
            return existingPersonName(app)
        }
        nameField.tap()
        nameField.typeText("Eleanor Wallner")
        attest(app)
        app.buttons["Continue"].tap()

        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 5) { notNow.tap() }

        skipTheDetailsFlow(app)
        app.buttons["onboarding.open-record"].tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        return "Eleanor Wallner"
    }

    private func existingPersonName(_ app: XCUIApplication) -> String {
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        let card = app.buttons["today.emergency-card"]
        scrollUntilHittable(card, in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let heading = app.staticTexts["emergency-card.name"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        let name = heading.label
        app.navigationBars.buttons.element(boundBy: 0).tap()
        return name
    }
}
