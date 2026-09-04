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

        // Picked from the menu as the reader, then typed over with a sibling's
        // name before saving.
        //
        // The save used to keep `assigneeUserID` for any non-empty name, and
        // `TaskPlanner.isAssigned` prefers the id whenever both sides have one,
        // so the row read "Dana" and belonged, invisibly, to the reader: it
        // survived the Mine filter under somebody else's name. The filter is
        // the feature that answers "what is mine", so an id disagreeing with
        // the name printed beside it is the one thing it must never do. Folded
        // into this test rather than given its own: a second launch of the
        // seeded family leaves another run's rows in the pool device's store,
        // and the tests after this one scroll past them.
        scope.buttons["Everyone"].tap()
        let retyped = "Collect the prescription \(run)"
        addTask(app, title: retyped, assignTo: "Robin", thenRenameTo: "Dana")

        scope.buttons["Mine"].tap()
        XCTAssertTrue(app.staticTexts[mine].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.staticTexts[retyped].exists,
            "a task renamed onto a sibling stayed assigned to the reader by id"
        )
        attach(app, named: "5-retyped-name-is-not-mine")
    }

    // MARK: Helpers

    private func openTasks(_ app: XCUIApplication) {
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
    }

    /// Adds a task assigned from the member menu rather than typed, which is
    /// the path that also writes `assigneeUserID` and so the one the filter
    /// matches on first.
    private func addTask(
        _ app: XCUIApplication,
        title: String,
        assignTo member: String,
        thenRenameTo renamed: String? = nil
    ) {
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

        if let renamed {
            let field = app.textFields["task-editor.assignee"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            let existing = (field.value as? String) ?? ""
            field.typeText(
                String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + renamed
            )
        }

        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
    }

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
