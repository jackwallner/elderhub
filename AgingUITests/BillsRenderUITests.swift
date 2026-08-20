import XCTest

/// Renders the bills screens, and the two audit fixes that are only visible on
/// screen.
///
/// Assertions that a row *exists* would pass on a list whose amounts are
/// clipped, whose sections are in the wrong order, or whose autopay row is
/// sitting in Overdue. The screenshots are the point; the assertions are there
/// to guarantee the screenshots are of the right screen.
@MainActor
final class BillsRenderUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testBillsListRendersEveryBucket() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        attach(app, named: "1-today-with-bills")

        // 10s, not 5: Today's nav bar paints before the seeded list does, so
        // the chip row is still being built when this runs. The sibling test
        // below already carries the longer wait for the same reason, and 5s
        // here fails intermittently on a loaded machine.
        let bills = app.buttons["today.quick.bills"]
        XCTAssertTrue(bills.waitForExistence(timeout: 10))
        bills.tap()

        XCTAssertTrue(app.navigationBars["Bills"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sunrise Assisted Living"].waitForExistence(timeout: 5))

        // Seeded to cover every bucket, so the shot shows the ordering rather
        // than one section repeated.
        XCTAssertTrue(app.staticTexts["Overdue"].exists)
        XCTAssertTrue(app.staticTexts["Due soon"].exists)
        XCTAssertTrue(app.staticTexts["On autopay"].exists)
        XCTAssertTrue(app.staticTexts["Still to pay"].exists)
        attach(app, named: "2-bills-list")

        app.swipeUp()
        attach(app, named: "3-bills-paid-section")
    }

    func testTheBillEditorSaysItIsNotAVault() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))

        // The nav bar paints before the seeded list does, so the chip row is
        // not on screen yet at that point. Tapping straight through fails
        // intermittently with "no matches found" while the app is still
        // building Today; wait for the chip itself, as the sibling test does.
        let bills = app.buttons["today.quick.bills"]
        XCTAssertTrue(bills.waitForExistence(timeout: 10))
        bills.tap()
        XCTAssertTrue(app.navigationBars["Bills"].waitForExistence(timeout: 5))

        app.buttons["bills.add"].tap()
        XCTAssertTrue(app.navigationBars["New Bill"].waitForExistence(timeout: 5))

        // Save stays off until there is a payee: a bill with no payee is a row
        // nobody can interpret later, exactly like a blank visit.
        let save = app.navigationBars["New Bill"].buttons["Save"]
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled)

        let payee = app.textFields["bill-editor.payee"]
        payee.tap()
        payee.typeText("City Water")
        XCTAssertTrue(save.isEnabled)

        app.swipeUp()
        attach(app, named: "4-bill-editor")
    }

    /// The audit's AUD-01: a record entered as "Eleanor Wallner" must not be
    /// titled "Mom" anywhere.
    func testTheEnteredNameIsTheLabelEverywhere() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        app.buttons["Care"].tap()
        let person = app.cells.element(boundBy: 0)
        XCTAssertTrue(person.waitForExistence(timeout: 5))
        person.tap()

        XCTAssertTrue(app.staticTexts["Medications"].waitForExistence(timeout: 5))
        attach(app, named: "5-hub-titled-by-name")

        // The whole point of AUD-01: the relationship must not be standing in
        // for the name anywhere on this screen.
        XCTAssertFalse(app.navigationBars["Mom"].exists)
        XCTAssertTrue(app.staticTexts["Eleanor Wallner"].exists)
        add(XCTAttachment(string: "nav bars: " + app.navigationBars.allElementsBoundByIndex.map(\.identifier).joined(separator: " | ")))
    }

    // MARK: - Helpers

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        // Wiped first: `seedIfEmpty` is a no-op on a simulator still holding an
        // earlier run's store, so without this the shots are of the old app.
        app.launchArguments += ["-uitest-wipe-store", "YES", "-seedDemo", "YES"]
        app.launch()
        // `-seedDemo` seeds both Mom and Dad, so Today opens on the aggregate.
        // Scope it to one of them: this bundle is testing a per-person screen.
        selectPersonOnToday(app, named: "Eleanor Wallner")
        return app
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
