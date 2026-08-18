import XCTest

/// Drives the real app with a second person in the care circle: assign two
/// tasks to two different people, then filter the list down to one of them.
///
/// `TaskPlanner.isAssigned` is unit-tested, but the part that was actually
/// missing was that nothing ever *read* the assignee. That is a view concern
/// end to end, so it is proved here: the control has to appear only in a shared
/// circle, "Mine" has to hide a sibling's errand, and the empty result has to
/// say why rather than look like an empty list.
@MainActor
final class CareTaskAssigneeFilterUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testTheListFiltersDownToTheReadersOwnErrands() {
        let app = XCUIApplication()
        // `-uitest-family` seeds a fresh circle with new ids on every launch,
        // which is what lets this assert that "Mine" is *empty* at one point:
        // a task a previous run on this pool device assigned to the reader
        // belongs to that run's ids and is correctly somebody else's now.
        app.launchArguments += ["-uitest-reset", "YES", "-uitest-family", "YES"]
        app.launch()

        completeOnboardingIfNeeded(app)

        let run = UUID().uuidString.prefix(4)
        let theirs = "Book the audiologist \(run)"
        let mine = "Order hearing aids \(run)"

        openTasks(app)

        // A sibling's errand first, so "Mine" has something to exclude and the
        // empty state is reachable before anything is assigned to the reader.
        addTask(app, title: theirs, assignTo: "Dana")

        let scope = app.segmentedControls["tasks.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5), "the assignee filter did not appear in a shared circle")
        attach(app, named: "1-everyone-one-sibling-task")

        scope.buttons["Mine"].tap()
        XCTAssertTrue(app.staticTexts["Nothing assigned to you"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[theirs].exists, "a sibling's task survived the Mine filter")
        attach(app, named: "2-mine-empty")

        // The way back out has to be on the screen, not only in the control.
        app.buttons["Show everyone's"].tap()
        XCTAssertTrue(app.staticTexts[theirs].waitForExistence(timeout: 5))

        addTask(app, title: mine, assignTo: "Robin")

        // Assigned to the reader, so the row says "You" rather than repeating
        // their own name back at them.
        XCTAssertTrue(app.staticTexts[mine].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "You")).firstMatch.exists,
            "the reader's own task did not read as theirs"
        )
        attach(app, named: "3-everyone-both-tasks")

        scope.buttons["Mine"].tap()
        XCTAssertTrue(app.staticTexts[mine].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[theirs].exists, "a sibling's task survived the Mine filter")
        attach(app, named: "4-mine-one-task")
    }

    // MARK: Helpers

    private func openTasks(_ app: XCUIApplication) {
        let medications = app.buttons["today.medications"]
        scrollToHittable(medications, in: app)
        XCTAssertTrue(medications.waitForExistence(timeout: 10))
        medications.tap()

        let tasks = app.buttons["person-detail.tasks"]
        scrollToHittable(tasks, in: app)
        XCTAssertTrue(tasks.waitForExistence(timeout: 5))
        tasks.tap()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))
    }

    /// Adds a task assigned from the member menu rather than typed, which is
    /// the path that also writes `assigneeUserID` and so the one the filter
    /// matches on first.
    private func addTask(_ app: XCUIApplication, title: String, assignTo member: String) {
        app.buttons["tasks.add"].tap()

        let titleField = app.textFields["task-editor.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(title)

        let picker = app.buttons["task-editor.assignee-picker"]
        scrollToHittable(picker, in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the family picker is missing from the editor")
        picker.tap()

        // Self is listed as "Name (you)"; everyone else by name alone.
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", member)).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "\(member) was not in the family picker")
        entry.tap()

        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
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

    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable {
            app.swipeUp()
        }
    }
}
