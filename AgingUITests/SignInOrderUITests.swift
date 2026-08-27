import XCTest

/// The order of first launch, which App Review rejected 1.0.1 over.
///
/// Guideline 4.0: an app offering Sign in with Apple may not then ask for a
/// name or an email that Authentication Services has already handed over. The
/// old flow signed in first and put a required name field on the very next
/// screen, so it read as exactly that even on the supporter path, where the
/// name being asked for belongs to the person being cared for rather than to
/// the account holder.
///
/// The fix is an ordering, and an ordering is only provable by walking it.
@MainActor
final class SignInOrderUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset", "YES", "-uitest-wipe-store", "YES"]
        app.launch()
        return app
    }

    /// The screen after the Apple button must ask for nothing at all. Asserted
    /// on the absence of *any* text field rather than on the name field alone:
    /// an email box added there later would be the same rejection.
    func testNothingIsAskedForAfterSignInWithApple() {
        let app = launchFresh()

        XCTAssertTrue(app.buttons["Start a care record"].waitForExistence(timeout: 5))
        app.buttons["Start a care record"].tap()

        let nameField = app.textFields["Their name"]
        XCTAssertTrue(
            nameField.waitForExistence(timeout: 5),
            "The record is named before any account is asked for"
        )
        XCTAssertFalse(
            app.buttons["Sign in with Apple"].exists,
            "Sign in with Apple appeared before the name step, which is the rejected order"
        )

        nameField.tap()
        nameField.typeText("Eleanor Wallner")
        attest(app)
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.buttons["Sign in with Apple"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.textFields.count, 0,
            "The Sign in with Apple screen asks for something the framework already provides"
        )
        XCTAssertEqual(app.secureTextFields.count, 0)

        // And nothing is asked for after it either: skipping lands straight in
        // the skippable details flow, which is about the person, not the account.
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.buttons["onboarding.details.skip"].waitForExistence(timeout: 5))
    }

    /// The solo path is the one that asks for the *account holder's* own name,
    /// so it is the one Apple's requirement is really about. It now runs before
    /// the account exists.
    func testTheSoloPathNamesYouBeforeItSignsYouIn() {
        let app = launchFresh()

        XCTAssertTrue(app.buttons["Keep track of myself"].waitForExistence(timeout: 5))
        app.buttons["Keep track of myself"].tap()

        XCTAssertTrue(app.textFields["Your name"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Sign in with Apple"].exists)
    }

    /// Backing out of the sign-in step has to take the draft record with it.
    /// The person is created before sign-in now, so a Back that left it behind
    /// would give a second one on the way forward, and Today would flip into
    /// its two-person Everyone mode on a phone tracking one person.
    func testBackingOutOfSignInLeavesNoSecondRecord() {
        let app = launchFresh()

        XCTAssertTrue(app.buttons["Start a care record"].waitForExistence(timeout: 5))
        app.buttons["Start a care record"].tap()

        let nameField = app.textFields["Their name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Eleanor Wallner")
        attest(app)
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.buttons["Sign in with Apple"].waitForExistence(timeout: 5))
        app.buttons["onboarding.back"].tap()

        // Round two, all the way through.
        XCTAssertTrue(app.buttons["Start a care record"].waitForExistence(timeout: 5))
        completeOnboarding(app)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))

        XCTAssertFalse(
            app.buttons["today.person-picker"].waitForExistence(timeout: 3),
            "Today opened in Everyone mode, so the abandoned draft was left behind"
        )

        app.buttons["Care"].tap()
        XCTAssertTrue(app.navigationBars["Care"].waitForExistence(timeout: 5))
        let rows = app.staticTexts.matching(NSPredicate(format: "label == %@", "Eleanor Wallner"))
        XCTAssertEqual(rows.count, 1, "The abandoned draft is still in the care list")
    }
}
