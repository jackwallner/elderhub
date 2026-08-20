import XCTest

/// The three things added for the "it is not obvious what this is or who it is
/// for" round: a setup checklist that can be dismissed a row at a time, a way
/// to run setup again from Settings, and handing the phone to the person being
/// looked after behind a caregiver code.
///
/// Screenshots are the point here too. "The button exists" is not evidence that
/// a card is the right width, that a keypad fits, or that the handed-over
/// screen still offers the emergency card.
@MainActor
final class SetupAndHandoverUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Dismissing one row must remove that row and leave the card, which is the
    /// whole difference between this and the Hide button beside it.
    func testASetupRowCanBeDismissedOnItsOwn() {
        let app = launchSeeded()

        let card = app.descendants(matching: .any).matching(identifier: "today.setup-card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        attach(app, named: "1-setup-card-at-top")

        let dismiss = app.buttons["Dismiss Invite the family"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        dismiss.tap()

        XCTAssertFalse(app.buttons["Dismiss Invite the family"].waitForExistence(timeout: 2))
        XCTAssertTrue(card.exists, "one row going away must not take the card with it")
        attach(app, named: "2-setup-card-after-dismiss")
    }

    /// Settings is where people look for a way back into setup, and the flow it
    /// opens has to skip every step without losing anything.
    func testSettingsCanRunSetupAgain() {
        let app = launchSeeded()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        attach(app, named: "3-settings-phone-and-setup")

        let rerun = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "settings.rerun-setup.")
        ).element(boundBy: 0)
        scrollTo(rerun, in: app)
        rerun.tap()

        let skip = app.buttons["onboarding.details.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        attach(app, named: "4-setup-again-step-1")

        // Every step skips, and skipping through all of them lands back on
        // Settings rather than stranding anyone mid-flow.
        for _ in 0..<8 where skip.exists {
            skip.tap()
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    /// The handed-over screen, and the code that comes back from it. The
    /// emergency card must be on that screen and must not be behind the code.
    func testHandingThePhoneOverAndComingBack() {
        let app = launchSeeded()

        app.buttons["Settings"].tap()
        let setCode = app.buttons["settings.caregiver-code"]
        scrollTo(setCode, in: app)
        setCode.tap()

        let fields = app.textFields
        XCTAssertTrue(fields.element(boundBy: 0).waitForExistence(timeout: 5))
        fields.element(boundBy: 0).tap()
        fields.element(boundBy: 0).typeText("1234")
        fields.element(boundBy: 1).tap()
        fields.element(boundBy: 1).typeText("1234")
        app.buttons["Save"].tap()

        let handOver = app.buttons["settings.hand-over"]
        XCTAssertTrue(handOver.waitForExistence(timeout: 5))
        scrollTo(handOver, in: app)
        handOver.tap()
        let candidateButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "settings.hand-over.")
        )
        if candidateButtons.firstMatch.waitForExistence(timeout: 2) {
            // The seeded circle has Eleanor first, so the capture covers Mom.
            candidateButtons.element(boundBy: 0).tap()
        } else {
            app.buttons["Switch to their view"].tap()
        }

        // Their whole app: one button, their medications, the emergency card.
        let unlock = app.buttons["check-in.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["check-in.emergency-card"].waitForExistence(timeout: 5))
        attach(app, named: "5-handed-over")

        // Reachable without the code. This is the ER-with-no-bars case and it
        // is the one thing the lock must never cover.
        app.buttons["check-in.emergency-card"].tap()
        XCTAssertTrue(app.navigationBars["Emergency Card"].waitForExistence(timeout: 5))
        attach(app, named: "6-emergency-card-while-locked")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        unlock.tap()
        attach(app, named: "7-caregiver-keypad")
        for digit in ["9", "9", "9", "9"] { app.buttons[digit].tap() }
        XCTAssertTrue(app.staticTexts["That code did not match."].waitForExistence(timeout: 5))

        // Back in the caregiver's app, on the tab it was handed over from
        // rather than reset to Today: `AppNavigator.tab` is state on the root,
        // and the root is not rebuilt by the swap. Coming back to Settings,
        // where the switch was thrown, is the right behaviour; it just means
        // the proof of "the full app is back" is the tab bar, not a title.
        for digit in ["1", "2", "3", "4"] { app.buttons[digit].tap() }
        XCTAssertTrue(app.buttons["Care"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Settings"].exists)
        attach(app, named: "8-back-in-the-full-app")

        app.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
    }

    // MARK: - Helpers

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-wipe-store", "YES", "-seedDemo", "YES"]
        app.launch()
        // `-seedDemo` seeds both Mom and Dad, so Today opens on the aggregate.
        // Scope it to one of them: this bundle is testing a per-person screen.
        selectPersonOnToday(app, named: "Eleanor Wallner")
        return app
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
