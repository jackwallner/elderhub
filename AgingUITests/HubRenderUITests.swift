import XCTest

/// Renders the screens the "it's not clear what this app does" complaint was
/// about, and attaches them.
///
/// A passing assertion that a tile *exists* is not proof that the hub reads
/// well: truncated blurbs, a count line that says "1 medications", tiles that
/// collide at large Dynamic Type and a setup card that stayed on screen after
/// being finished all pass an existence check. The screenshots are the point;
/// the assertions just guarantee the screenshots are of the right screen.
@MainActor
final class HubRenderUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testTodayAndThePersonHubRenderTheirFeatures() {
        let app = XCUIApplication()
        // Seeded rather than freshly onboarded: an empty record renders empty
        // tiles, and the thing being checked here is how a real record reads.
        // Wiped first: `SampleData.seedIfEmpty` is a no-op on a simulator that
        // already holds an earlier run's demo store, so without this the shots
        // are of whatever the app looked like the last time it was seeded.
        app.launchArguments += ["-uitest-wipe-store", "YES", "-seedDemo", "YES"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        let medical = app.buttons["today.quick.medical"]
        XCTAssertTrue(medical.waitForExistence(timeout: 5))
        attach(app, named: "1-today-quick-actions")

        // The two big destinations are below the chips, so this is also the
        // proof that the doses list and the emergency card survive the setup
        // card being moved to the top.
        app.swipeUp()
        attach(app, named: "1a-today-doses-and-cards")
        app.swipeDown()

        // Medical pushes a screen of tiles rather than dropping a menu of bare
        // words. The proof that the rest of the record is still reachable is
        // that the screen opens and holds it.
        XCTAssertTrue(medical.waitForExistence(timeout: 5))
        medical.tap()
        XCTAssertTrue(app.navigationBars["Medical"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["medical.vitals"].waitForExistence(timeout: 5))
        attach(app, named: "1b-today-medical-hub")
        app.buttons["medical.vitals"].tap()
        XCTAssertTrue(app.navigationBars["Vitals"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Notes is the one screen with no shape of its own, so what is being
        // checked is that a seeded pile renders as rows rather than as a wall.
        XCTAssertTrue(app.buttons["today.quick.notes"].waitForExistence(timeout: 5))
        app.buttons["today.quick.notes"].tap()
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Getting into the house"].waitForExistence(timeout: 5))
        attach(app, named: "1c-today-notes")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Care"].tap()
        let person = app.cells.element(boundBy: 0)
        XCTAssertTrue(person.waitForExistence(timeout: 5))
        attach(app, named: "2-people-setup-progress")
        person.tap()

        XCTAssertTrue(app.staticTexts["Medications"].waitForExistence(timeout: 5))
        attach(app, named: "3-hub-header")

        let vitals = app.buttons["person-detail.vitals"]
        scrollToHittable(vitals, in: app)
        XCTAssertTrue(vitals.exists)
        attach(app, named: "4-hub-everyday-tiles")

        let timeline = app.buttons["person-detail.timeline"]
        scrollToHittable(timeline, in: app)
        XCTAssertTrue(timeline.exists)
        attach(app, named: "5-hub-records-and-er")

        // The tiles have to actually go somewhere. Ten links nested inside a
        // grid inside a list row look identical on screen to ten that work.
        timeline.tap()
        XCTAssertTrue(app.navigationBars["Timeline"].waitForExistence(timeout: 5))
        attach(app, named: "6-timeline")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        scrollToHittable(vitals, in: app)
        vitals.tap()
        XCTAssertTrue(app.navigationBars["Vitals"].waitForExistence(timeout: 5))
    }

    func testTodayQuickActionsRemainUsableAtAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uitest-wipe-store", "YES",
            "-seedDemo", "YES",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["today.quick.medications"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["today.quick.notes"].exists)
        attach(app, named: "today-accessibility-text")
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
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
