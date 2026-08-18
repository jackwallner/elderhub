import XCTest

/// Renders the real paywall under StoreKit Testing and attaches a screenshot.
///
/// The scheme's `Products.storekit` configuration applies automatically under
/// `xcodebuild test`, so the plan cards resolve from the local catalog. Plain
/// `simctl launch` bypasses the scheme and only ever shows the empty state, so
/// paywall layout must be verified here rather than from a `simctl` screenshot.
// Every `XCUIApplication` touch is main-actor work. Without this the helpers
// below are non-isolated and Swift 6 warns on each one; the other three UI test
// classes already carry it.
@MainActor
final class PaywallRenderUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testPaywallRendersPlans() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset", "YES", "-uitest-wipe-store", "YES"]
        app.launch()

        completeOnboardingIfNeeded(app)

        // Free tier covers one person, so adding a second opens the paywall.
        app.buttons["Care"].tap()
        XCTAssertTrue(app.navigationBars["Care"].waitForExistence(timeout: 5))
        app.buttons["Add person"].tap()

        let monthly = app.buttons["paywall.plan.com.jackwallner.aging.pro.monthly"]
        XCTAssertTrue(
            monthly.waitForExistence(timeout: 15),
            "Paywall did not render plans. StoreKit Testing may not be active for this run."
        )

        // Capture before asserting, so a failure still leaves usable evidence.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "paywall"
        shot.lifetime = .keepAlways
        add(shot)

        let rendered = app.buttons.allElementsBoundByIndex
            .compactMap { $0.identifier }
            .filter { $0.hasPrefix("paywall.plan.") }
        add(XCTAttachment(string: "rendered plan cards:\n" + rendered.joined(separator: "\n")))

        // All three plans, priced, is what makes this a usable review screenshot.
        for productID in [
            "com.jackwallner.aging.pro.monthly",
            "com.jackwallner.aging.pro.yearly",
            "com.jackwallner.aging.pro.lifetime"
        ] {
            XCTAssertTrue(
                app.buttons["paywall.plan.\(productID)"].exists,
                "Missing plan card for \(productID). Rendered: \(rendered)"
            )
        }
    }

    private func completeOnboardingIfNeeded(_ app: XCUIApplication) {
        let start = app.buttons["Start a care record"]
        if start.waitForExistence(timeout: 5) {
            start.tap()
            app.buttons["Not now"].tap()
        }

        let nameField = app.textFields["Their name"]
        guard nameField.waitForExistence(timeout: 10) else { return }

        nameField.tap()
        nameField.typeText("Eleanor Wallner")
        app.buttons["Continue"].tap()
        skipTheDetailsFlow(app)
        app.buttons["onboarding.open-record"].tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
    }
}
