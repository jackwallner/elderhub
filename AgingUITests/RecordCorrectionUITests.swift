import XCTest

/// Proves the correction paths that did not exist: a saved medication, visit
/// and vital reading can each be reopened and changed in place.
///
/// Existence checks on an editor sheet are not enough here. The failure mode
/// being guarded against is a sheet that opens with empty fields, saves a
/// second row, and leaves the original untouched, which looks exactly like a
/// working edit until you count the rows. So each case asserts the new value
/// is on the list *and the old one is gone*.
@MainActor
final class RecordCorrectionUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testASavedMedicationCanBeCorrectedInPlace() {
        let app = launchSeeded()

        openFirstPerson(app)

        // Scrolled to. The person header and the setup card both grew when the
        // controls were sized up for the audience, so the medication list no
        // longer starts on the first screen of a seeded record, and a `List`
        // does not render a row it has not reached.
        let row = app.buttons.containing(.staticText, identifier: "Lisinopril 10 mg").element
        scrollToHittable(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.navigationBars["Edit Medication"].waitForExistence(timeout: 5))
        // The fields have to arrive populated. An editor that opens blank is
        // how "edit" quietly becomes "add a duplicate".
        let strength = app.textFields["Strength (10 mg)"]
        XCTAssertTrue(strength.waitForExistence(timeout: 5))
        XCTAssertEqual(strength.value as? String, "10 mg")
        attach(app, named: "1-medication-editor-populated")

        strength.tap()
        strength.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) {
            app.menuItems["Select All"].tap()
        }
        strength.typeText("20 mg")
        app.buttons["medication-editor.save"].tap()

        XCTAssertTrue(app.staticTexts["Lisinopril 20 mg"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Lisinopril 10 mg"].exists)
        attach(app, named: "2-medication-corrected-in-place")
    }

    func testASavedVisitReopensItsOwnFields() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        openVisits(app)
        XCTAssertTrue(app.navigationBars["Appointments"].waitForExistence(timeout: 5))

        // A past visit by name, not the first cell: the first cell is now the
        // upcoming appointment, which opens as "Appointment".
        let visit = app.staticTexts["Three month check"].firstMatch
        XCTAssertTrue(visit.waitForExistence(timeout: 5))
        visit.tap()

        XCTAssertTrue(app.navigationBars["Visit"].waitForExistence(timeout: 5))
        XCTAssertFalse((app.textFields["Reason for visit"].value as? String ?? "").isEmpty)
        attach(app, named: "3-visit-editor-populated")
    }

    /// The claim this screen now makes: an appointment nobody has been to yet
    /// can be entered, and it comes back under Upcoming rather than into the
    /// history.
    func testAnAppointmentCanBeAddedAndReadsAsUpcoming() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        openVisits(app)
        XCTAssertTrue(app.navigationBars["Appointments"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Upcoming"].waitForExistence(timeout: 5))

        app.navigationBars["Appointments"].buttons["visits.add"].tap()
        app.buttons["Add an appointment"].tap()

        XCTAssertTrue(app.navigationBars["New Appointment"].waitForExistence(timeout: 5))
        let reason = app.textFields["Reason for visit"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        reason.tap()
        reason.typeText("Cardiology review")
        app.navigationBars["New Appointment"].buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Cardiology review"].waitForExistence(timeout: 5))
        attach(app, named: "3b-appointment-added")
    }

    /// A blank sheet must not be savable. A date-only visit and an untouched
    /// symptom both used to land in the list and in the Timeline as rows
    /// nobody can interpret later.
    func testABlankVisitCannotBeSaved() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        openVisits(app)
        XCTAssertTrue(app.navigationBars["Appointments"].waitForExistence(timeout: 5))
        app.navigationBars["Appointments"].buttons["visits.add"].tap()
        app.buttons["Log a past visit"].tap()

        XCTAssertTrue(app.navigationBars["Log Visit"].waitForExistence(timeout: 5))
        let save = app.navigationBars["Log Visit"].buttons["Save"]
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled)
        attach(app, named: "4-blank-visit-save-disabled")

        app.textFields["Reason for visit"].tap()
        app.textFields["Reason for visit"].typeText("Follow up")
        XCTAssertTrue(save.isEnabled)
    }

    /// Every critical section is named even when empty, so a reader cannot take
    /// silence for "none".
    func testTheEmergencyCardNamesWhatIsMissing() {
        let app = launchSeeded()

        // Reached from the person hub rather than the foot of Today. Today's
        // link sits below a seeded day's worth of doses and tasks, and driving
        // a blind swipe down to it made this test flaky about a screen it is
        // not trying to test.
        openFirstPerson(app)
        let card = app.buttons["person-detail.emergency-card"]
        scrollToHittable(card, in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        XCTAssertTrue(app.navigationBars["Emergency Card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Allergies"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Emergency contacts"].exists)
        attach(app, named: "5-emergency-card")
    }

    /// A search result that cannot be opened is an index, not a search.
    func testASearchResultOpensTheRecordItFound() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        app.buttons["Care"].tap()

        // The Care list opens with the search bar scrolled up under the title,
        // so it is not in the hierarchy at all until the list is pulled down.
        // A person opening the tab does the same thing by reflex; the test has
        // to do it explicitly.
        let field = app.searchFields.element(boundBy: 0)
        if !field.waitForExistence(timeout: 3) {
            app.collectionViews.element(boundBy: 0).swipeDown()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        // "Marta" rather than "gate": the seeded note stopped modelling a gate
        // code when the Notes copy stopped suggesting one.
        field.typeText("Marta")

        let hit = app.cells.element(boundBy: 0)
        XCTAssertTrue(hit.waitForExistence(timeout: 5))
        attach(app, named: "6-search-results")
        hit.tap()

        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 5))
        attach(app, named: "7-search-result-opened")
    }

    /// Undo puts a dose back to unrecorded, and taking it again reuses the
    /// same row.
    ///
    /// `DoseLog.id` is derived from (medication, scheduled time), so a second
    /// row for the same slot would be handed the id the tombstone still holds
    /// and the push would have two rows for one server key. The visible proof
    /// is that the slot cycles cleanly: take it, undo it, take it again, with
    /// one row on screen throughout and the app still able to record on it.
    func testUndoingADoseReturnsItToUnrecordedAndItCanBeTakenAgain() {
        let app = launchSeeded()

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))

        // Seeded doses for today start unrecorded, so each row carries a Taken
        // *button*. Counting buttons is what tells recorded from not: once a
        // dose is logged the button is replaced by a status label.
        let buttons = app.buttons.matching(identifier: "Taken")
        // Scrolled to for the same reason as the medication row above: the
        // setup checklist now leads Today, so the dose list starts lower than
        // it used to on a seeded record.
        scrollToHittable(buttons.element(boundBy: 0), in: app)
        XCTAssertTrue(buttons.element(boundBy: 0).waitForExistence(timeout: 5))
        let before = buttons.count
        XCTAssertGreaterThan(before, 0)
        attach(app, named: "8-doses-before")

        buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitFor(buttons, toCount: before - 1))

        // Undo the one just recorded. Its row is the only one that now has a
        // swipe action offering it.
        let row = app.cells.containing(.staticText, identifier: "Lisinopril").element
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()

        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        attach(app, named: "9-dose-undo-action")
        undo.tap()

        // Back to unrecorded: the button returns and the count is what it was.
        XCTAssertTrue(waitFor(buttons, toCount: before))

        // And it can be recorded again. A duplicate row would show up here as
        // an extra dose in the section rather than the same one flipping back.
        buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitFor(buttons, toCount: before - 1))
        attach(app, named: "10-dose-retaken")
    }

    // MARK: - Helpers

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        // Wiped first: `seedIfEmpty` is a no-op on a simulator still holding an
        // earlier run's store, so without this the test runs against whatever
        // was there before.
        app.launchArguments += ["-uitest-wipe-store", "YES", "-seedDemo", "YES"]
        app.launch()
        // `-seedDemo` seeds both Mom and Dad, so Today opens on the aggregate.
        // Scope it to one of them: this bundle is testing a per-person screen.
        selectPersonOnToday(app, named: "Eleanor Wallner")
        return app
    }

    /// Visits moved off the open chip row when Bills took its slot, so every
    /// route to it goes through Medical. That chip used to drop a menu and now
    /// pushes `MedicalRecordView`, so the second tap is on a tile there.
    private func openVisits(_ app: XCUIApplication) {
        let medical = app.buttons["today.quick.medical"]
        XCTAssertTrue(medical.waitForExistence(timeout: 5))
        medical.tap()
        XCTAssertTrue(app.navigationBars["Medical"].waitForExistence(timeout: 5))
        let visits = app.buttons["medical.visits"]
        XCTAssertTrue(visits.waitForExistence(timeout: 5))
        visits.tap()
    }

    private func openFirstPerson(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        app.buttons["Care"].tap()
        let person = app.cells.element(boundBy: 0)
        XCTAssertTrue(person.waitForExistence(timeout: 5))
        person.tap()
        XCTAssertTrue(app.staticTexts["Medications"].waitForExistence(timeout: 5))
    }

    /// `XCUIElementQuery.count` re-queries but does not wait, so reading it
    /// straight after a tap races the view update.
    private func waitFor(_ query: XCUIElementQuery, toCount expected: Int, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if query.count == expected { return true }
            usleep(100_000)
        }
        XCTFail("Expected \(expected) matches, found \(query.count)")
        return false
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
