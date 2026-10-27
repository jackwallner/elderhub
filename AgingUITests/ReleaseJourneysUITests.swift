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

    /// The loop the app exists for: put a medication on the record, take the
    /// dose from Today, and find both still there after a relaunch.
    func testCoreLoopAddMedicationTakeDoseSurvivesRelaunch() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.aging")
        QA.launch(app, arguments: ["-uitest-reset", "YES", "-uitest-wipe-store", "YES"])
        completeOnboarding(app)
        today("core-today-empty", in: app)

        let drug = "Metformin"
        let strength = "500 mg"
        openMedications(in: app)
        let add = app.buttons["person-detail.add-medication"]
        scrollUntilHittable(add, in: app)
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()

        let nameField = app.textFields["Medication name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 15))
        nameField.tap()
        nameField.typeText(drug)
        let strengthField = app.textFields["Strength (10 mg)"]
        XCTAssertTrue(strengthField.waitForExistence(timeout: 5))
        strengthField.tap()
        strengthField.typeText(strength)
        QA.checkpoint(app, "core-med-editor")
        app.buttons["medication-editor.save"].tap()

        let listed = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", drug)).firstMatch
        XCTAssertTrue(listed.waitForExistence(timeout: 15), "the saved medication is not on the record")
        QA.checkpoint(app, "core-med-listed")

        let take = takeButton(drug, in: app)
        returnToToday(until: take, in: app)
        XCTAssertTrue(take.waitForExistence(timeout: 15), "Today shows no dose to take for \(drug)")
        QA.checkpoint(app, "core-dose-due")
        take.tap()

        let status = doseStatus(drug, in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 10), "the dose did not record")
        XCTAssertTrue(status.label.hasSuffix("Taken"), "dose status was \(status.label)")
        XCTAssertFalse(take.exists)
        QA.checkpoint(app, "core-dose-taken")

        QA.relaunch(app)
        today("core-after-relaunch", in: app)
        let after = doseStatus(drug, in: app)
        for _ in 0..<6 where !after.exists { app.swipeUp() }
        XCTAssertTrue(after.waitForExistence(timeout: 15), "the taken dose is gone after relaunch")
        XCTAssertTrue(after.label.hasSuffix("Taken"), "dose status after relaunch was \(after.label)")
        XCTAssertFalse(takeButton(drug, in: app).exists)
        QA.checkpoint(app, "core-dose-kept")
    }

    private func takeButton(_ drug: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Mark \(drug) at")).firstMatch
    }

    private func doseStatus(_ drug: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(drug) at")).firstMatch
    }

    private func openMedications(in app: XCUIApplication) {
        selectPersonOnToday(app, named: "Eleanor Wallner")
        let record = app.buttons["today.medications"]
        scrollUntilHittable(record, in: app)
        XCTAssertTrue(record.waitForExistence(timeout: 15))
        record.tap()
    }

    /// Pops back with the back button named for Today, which folded is the
    /// previous screen and unfolded does not exist because Today stays beside
    /// the record.
    private func returnToToday(until element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<3 where !element.exists {
            let back = app.navigationBars.buttons["Today"]
            guard back.exists else { break }
            back.tap()
            _ = element.waitForExistence(timeout: 3)
        }
        for _ in 0..<6 where !element.exists { app.swipeDown() }
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

    private func checkpoint(_ name: String, button label: String, in app: XCUIApplication, journey: String = #function) {
        XCTAssertTrue(app.buttons[label].firstMatch.waitForExistence(timeout: 15))
        QA.checkpoint(app, name, journey: journey)
    }

    private func today(_ name: String, in app: XCUIApplication, journey: String = #function) {
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 20))
        QA.checkpoint(app, name, journey: journey)
    }
}
