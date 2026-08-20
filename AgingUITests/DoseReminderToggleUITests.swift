import XCTest

/// Renders the per-person dose reminder toggle and attaches a screenshot.
///
/// The toggle is only reachable by walking the app, and the simulator cannot be
/// driven from `simctl`, so this is the headless way to see it. It deliberately
/// does not tap the toggle: turning it on asks for notification permission, and
/// a system alert would block the rest of the run.
@MainActor
final class DoseReminderToggleUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testPersonDetailShowsTheDoseReminderToggle() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset", "YES"]
        app.launch()

        completeOnboardingIfNeeded(app)

        // The Today tab now opens with a quick-action row and can carry a day's
        // worth of doses above this link, and a `List` does not render rows it
        // has not scrolled to, so this has to be scrolled into view first.
        // A `-seedDemo` bundle earlier in the run can leave a two-person store
        // behind (`-uitest-reset` clears onboarding, not the store), and Today
        // opens on the aggregate whenever there is more than one person. A
        // no-op when this device really does hold one.
        selectPersonOnToday(app, named: "Eleanor Wallner")
        let medications = app.buttons["today.medications"]
        scrollToHittable(medications, in: app)
        XCTAssertTrue(medications.waitForExistence(timeout: 10))
        medications.tap()

        // The hub opens with the header stats, the setup checklist and the
        // medication list above this, so it has to be scrolled to as well.
        let toggle = app.switches["person-detail.dose-reminders"]
        scrollToHittable(toggle, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "person-detail-dose-reminders"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(app.staticTexts["Reminders"].exists)
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func completeOnboardingIfNeeded(_ app: XCUIApplication) {
        let supporter = app.buttons["Start a care record"]
        if supporter.waitForExistence(timeout: 5) {
            supporter.tap()
        }

        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 5) {
            notNow.tap()
        }

        let nameField = app.textFields["Their name"]
        if nameField.waitForExistence(timeout: 5) {
            nameField.tap()
            nameField.typeText("Eleanor Wallner")
            app.buttons["Continue"].tap()
            skipTheDetailsFlow(app)
            app.buttons["onboarding.open-record"].tap()
        }

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
    }
}
