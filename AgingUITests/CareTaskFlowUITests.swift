import XCTest

/// Drives the real app: add a task, see it on the Today tab, tick it off.
///
/// The whole point of a shared task list is the round trip between the list and
/// the Today tab, and neither a unit test over `TaskPlanner` nor a snapshot of
/// the sheet proves it. Screenshots are attached at every step so the rendered
/// result can be read against the fleet checklist rather than inferred from a
/// passing assertion.
@MainActor
final class CareTaskFlowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testATaskAddedInTheListShowsOnTodayAndCanBeTickedOff() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset", "YES"]
        app.launch()

        completeOnboardingIfNeeded(app)

        // `-uitest-reset` clears onboarding, not the store, so the title has to
        // be unique per run or this asserts against a previous run's leftovers.
        let title = "Pharmacy refill \(UUID().uuidString.prefix(4))"

        XCTAssertFalse(app.staticTexts[title].exists)
        attach(app, named: "1-today-before")

        // A day of doses can sit above this link and a `List` does not
        // render rows it has not scrolled to, so scroll first.
        // A `-seedDemo` bundle earlier in the run can leave a two-person store
        // behind (`-uitest-reset` clears onboarding, not the store), and Today
        // opens on the aggregate whenever there is more than one person. A
        // no-op when this device really does hold one.
        selectPersonOnToday(app, named: "Eleanor Wallner")
        let medications = app.buttons["today.medications"]
        scrollToHittable(medications, in: app)
        XCTAssertTrue(medications.waitForExistence(timeout: 10))
        medications.tap()

        let tasks = app.buttons["person-detail.tasks"]
        scrollToHittable(tasks, in: app)
        XCTAssertTrue(tasks.waitForExistence(timeout: 5))
        tasks.tap()

        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))
        attach(app, named: "2-tasks-empty")

        app.buttons["tasks.add"].tap()

        let titleField = app.textFields["task-editor.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(title)

        // Due today, so it is expected to land on the Today tab as well.
        // Tapped at the trailing edge rather than at the row's centre: a plain
        // `.tap()` on a Form toggle lands on the label and leaves the switch
        // alone, which silently produced an undated task here.
        let dueDate = app.switches["Due date"]
        XCTAssertTrue(dueDate.waitForExistence(timeout: 5))
        // Scrolled into view before the tap. Typing the title leaves the
        // keyboard up, and a coordinate tap on a row sitting behind it lands on
        // a key instead of the switch, which shows up here as a toggle that
        // simply did not move.
        scrollToHittable(dueDate, in: app)
        XCTAssertTrue(dueDate.isHittable, "the due-date row was not reachable to tap")
        dueDate.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(dueDate.value as? String, "1", "the due-date toggle did not turn on")

        // The period a family actually reorders hearing aids on. It only exists
        // in the picker as of the quarterly/half-yearly cases, and a menu-style
        // Picker renders nothing until it is opened, so this is the only place
        // the option is proved to be reachable rather than merely declared.
        let repeatPicker = app.buttons["task-editor.repeat"]
        scrollToHittable(repeatPicker, in: app)
        XCTAssertTrue(repeatPicker.waitForExistence(timeout: 5))
        repeatPicker.tap()
        let quarterly = app.buttons["Every 3 months"]
        XCTAssertTrue(quarterly.waitForExistence(timeout: 5))
        attach(app, named: "3-repeat-options")
        quarterly.tap()

        let assignee = app.textFields["task-editor.assignee"]
        scrollToHittable(assignee, in: app)
        assignee.tap()
        assignee.typeText("Sarah")

        attach(app, named: "4-task-editor")
        app.buttons["Save"].tap()

        // Ten, not five: saving dismisses a sheet and rebuilds the list, and on
        // a loaded machine that has run over five seconds without anything
        // being wrong.
        let row = app.staticTexts[title]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        // The row's short form. "every 3 months" was longer than most task
        // titles, which is why `shortLabel` exists.
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "quarterly")).firstMatch
                .waitForExistence(timeout: 5),
            "the saved task did not show its repeat on the row"
        )
        // Which bucket header it landed under is asserted in `CareTaskTests`,
        // against `TaskPlanner` directly: section headers are styled text with
        // no stable identifier, and matching on them makes this test brittle
        // for no extra coverage. What matters here is the Today-tab round trip
        // below, which is the thing no unit test can prove.
        attach(app, named: "5-tasks-with-one-open")

        // Back to Today, where the same task has to be actionable.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))

        // Back at whatever scroll offset Today was left at, which after the
        // trip through the hub can be most of a seeded day down the list. Tasks
        // is near the top and a `List` does not keep rows it has scrolled past,
        // so the row genuinely does not exist until the list is back at the top.
        let todayRow = app.staticTexts[title]
        for _ in 0..<8 where !todayRow.exists {
            app.swipeDown()
        }
        XCTAssertTrue(todayRow.waitForExistence(timeout: 5))
        attach(app, named: "6-today-with-task")

        app.buttons["Mark \(title) done"].tap()

        // Ticking it off removes it from Today, because Today is what is left.
        XCTAssertFalse(todayRow.waitForExistence(timeout: 2))
        attach(app, named: "7-today-after-completing")
    }

    // MARK: Helpers

    private func attach(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The steps live in `OnboardingHelpers` rather than here, which is the
    /// only reason the sign-in reorder did not have to be made in six places.
    private func completeOnboardingIfNeeded(_ app: XCUIApplication) {
        completeOnboarding(app)
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
    }

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable {
            app.swipeUp()
        }
    }
}
