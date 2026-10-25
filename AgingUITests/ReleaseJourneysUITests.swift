import XCTest

@MainActor
final class ReleaseJourneysUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func test1FirstRecordToTodayAndUpgrade() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.aging")
        QA.launch(app, arguments: ["-uitest-reset", "YES", "-uitest-wipe-store", "YES"])
        checkpoint("fork", button: "Start a care record", in: app)
        tap("Start a care record", in: app)
        let name = app.textFields["Their name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        QA.checkpoint(app, "name")
        name.tap()
        name.typeText("Eleanor Wallner")
        attest(app)
        tap("Continue", in: app)
        checkpoint("sign-in", button: "Not now", in: app)
        tap("Not now", in: app)
        let skip = app.buttons["onboarding.details.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        QA.checkpoint(app, "details")
        skipTheDetailsFlow(app)
        let open = app.buttons["onboarding.open-record"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        QA.checkpoint(app, "overview")
        open.tap()
        today("first-today", in: app)
        tapTab("Care", in: app)
        XCTAssertTrue(app.navigationBars["Care"].waitForExistence(timeout: 10))
        tap("Add person", in: app)
        XCTAssertTrue(app.buttons["paywall.plan.com.jackwallner.aging.pro.monthly"].waitForExistence(timeout: 20))
        QA.checkpoint(app, "upgrade", paywall: true)
        tap("Not now", in: app)
        XCTAssertTrue(app.navigationBars["Care"].waitForExistence(timeout: 10))
        QA.checkpoint(app, "care-after-upgrade")
    }

    func test2TabsAndReturn() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.aging")
        QA.launch(app, arguments: ["-seedDemo", "YES"])
        today("today", in: app)
        for tab in ["Care", "Sharing", "Settings"] {
            tapTab(tab, in: app)
            QA.checkpoint(app, tab.lowercased())
        }
        tapTab("Today", in: app)
        today("today-after-tabs", in: app)
        QA.interrupt(app)
        today("today-after-background", in: app)
        QA.relaunch(app)
        today("today-after-relaunch", in: app)
    }

    private func tap(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
    }

    private func tapTab(_ label: String, in app: XCUIApplication) {
        let button = app.tabBars.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
    }

    private func checkpoint(_ name: String, button label: String, in app: XCUIApplication) {
        XCTAssertTrue(app.buttons[label].firstMatch.waitForExistence(timeout: 15))
        QA.checkpoint(app, name)
    }

    private func today(_ name: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 20))
        QA.checkpoint(app, name)
    }
}
