import XCTest

@MainActor
final class NavigationFlowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testEmergencyCardAndContactsOpenTheirOwnDestinations() {
        let app = XCUIApplication()
        // Wiped as well as reset. Resetting only clears the onboarding flag, so
        // on a simulator still holding an earlier test's demo store this walked
        // straight past `completeOnboardingIfNeeded` and ran against a seeded
        // record two screens long, where the last section is genuinely not
        // rendered yet. The test means "onboard, then navigate", so it has to
        // start from nothing, the way its sibling below already does.
        app.launchArguments += ["-uitest-reset", "YES", "-uitest-wipe-store", "YES"]
        app.launch()

        completeOnboardingIfNeeded(app)

        // Scrolled to, like its sibling below. On a record with nothing in it
        // the setup checklist now leads the screen and the two big cards sit
        // under the action grid, so this is below the fold on first launch and
        // a `List` does not render what it has not scrolled to. See
        // `docs/architecture.md` §19 for why that is an acceptable place for
        // the emergency card to be on an empty record and nowhere else.
        let todayCard = app.buttons["today.emergency-card"]
        scrollToHittable(todayCard, in: app)
        XCTAssertTrue(todayCard.waitForExistence(timeout: 10))
        todayCard.tap()
        XCTAssertTrue(app.navigationBars["Emergency Card"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let medications = app.buttons["today.medications"]
        scrollToHittable(medications, in: app)
        XCTAssertTrue(medications.waitForExistence(timeout: 5))
        medications.tap()

        let contacts = app.buttons["person-detail.emergency-contacts"]
        scrollToHittable(contacts, in: app)
        XCTAssertTrue(contacts.waitForExistence(timeout: 5))
        XCTAssertTrue(contacts.isHittable)
        contacts.tap()
        XCTAssertTrue(app.navigationBars["Emergency Contacts"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let personCard = app.buttons["person-detail.emergency-card"]
        scrollToHittable(personCard, in: app)
        XCTAssertTrue(personCard.isHittable)
        personCard.tap()
        XCTAssertTrue(app.navigationBars["Emergency Card"].waitForExistence(timeout: 5))
    }

    func testFreshOnboardingExplainsTheCareRecordBeforeToday() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset", "YES", "-uitest-wipe-store", "YES"]
        app.launch()

        XCTAssertTrue(app.buttons["Start a care record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["I have an invitation"].exists)
        XCTAssertTrue(app.buttons["Keep track of myself"].exists)

        app.buttons["Start a care record"].tap()

        // The record is named before any account is asked for. 1.0.1 was
        // rejected under Guideline 4.0 for the other order: a required name
        // field on the screen straight after Sign in with Apple, which the
        // Authentication Services framework has already provided.
        let name = app.textFields["Their name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Eleanor Wallner")
        attest(app)
        app.buttons["Continue"].tap()

        let notNow = app.buttons["Not now"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["Sign in with Apple"].exists,
            "The sign-in step no longer follows the name step"
        )
        notNow.tap()

        // Every question is skippable, and the first thing this proves is that
        // Skip is reachable at all: a flow this long with a Skip below the fold
        // would be a flow nobody can get out of.
        XCTAssertTrue(app.buttons["onboarding.details.skip"].waitForExistence(timeout: 5))
        skipTheDetailsFlow(app)

        XCTAssertTrue(app.staticTexts["Eleanor Wallner’s care record is ready"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Medications and doses"].exists)
        XCTAssertTrue(app.staticTexts["Emergency card"].exists)
        XCTAssertTrue(app.staticTexts["Looking after more than one person?"].exists)

        app.buttons["onboarding.open-record"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set up Eleanor Wallner's record"].exists)
    }

    private func completeOnboardingIfNeeded(_ app: XCUIApplication) {
        completeOnboarding(app)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
    }
}
