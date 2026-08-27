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
        // This is a render test over the seeded medication record. Wipe the
        // persistent simulator store so an earlier UI test cannot leave the
        // Today aggregate selected or add enough rows to move the card out of
        // the bounded scroll window.
        app.launchArguments += ["-uitest-wipe-store", "YES", "-seedDemo", "YES"]
        app.launch()

        completeOnboardingIfNeeded(app)

        // The demo record has two people so shared-screen rendering is covered
        // elsewhere. Pick Eleanor before walking into her full record.
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

    /// The steps live in `OnboardingHelpers` rather than here, which is the
    /// only reason the sign-in reorder did not have to be made in six places.
    private func completeOnboardingIfNeeded(_ app: XCUIApplication) {
        completeOnboarding(app)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
    }
}
