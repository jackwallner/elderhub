import XCTest

/// Persona audit walk: someone who has used Elderhub for months and repeats the
/// same jobs every day (tick off the morning doses, log a reading, add a
/// recurring errand, restock a bottle, find an old note) and who goes looking
/// for the faster or deeper way to do each. Runs on the public demo fixture
/// (`-seedDemo`), which holds two people, years of history, tasks and bills.
///
/// Photographs a screen at each step and logs control sizes and tap counts, and
/// asserts almost nothing so a surprising screen is captured, not aborted on.
@MainActor
final class ExperiencedAuditUITests: XCTestCase {

    private var log: [String] = []

    override func setUp() {
        continueAfterFailure = true
        log = []
    }

    override func tearDown() {
        let text = XCTAttachment(string: log.joined(separator: "\n"))
        text.name = "control-log"
        text.lifetime = .keepAlways
        add(text)
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func probe(_ element: XCUIElement, _ name: String) {
        guard element.exists else {
            log.append("\(name): MISSING")
            return
        }
        let f = element.frame
        log.append("\(name): \(Int(f.width))x\(Int(f.height)) at (\(Int(f.minX)),\(Int(f.minY))) hittable=\(element.isHittable) enabled=\(element.isEnabled)")
    }

    private func note(_ line: String) { log.append("NOTE: \(line)") }

    private func launchSeeded(family: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset", "YES", "-uitest-wipe-store", "YES", "-seedDemo", "YES"]
        if family { app.launchArguments += ["-uitest-family", "YES"] }
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 20))
        sleep(1)
        return app
    }

    private func back(_ app: XCUIApplication) {
        let bar = app.navigationBars.element(boundBy: 0)
        let button = bar.buttons.element(boundBy: 0)
        if button.exists, button.isHittable { button.tap() }
        sleep(1)
    }

    private func count(_ query: XCUIElementQuery) -> Int { query.count }

    // MARK: - Daily loop: Everyone mode

    func testExperiencedMorningRoundEveryone() {
        let app = launchSeeded()
        shot(app, "01-today-everyone-first")
        probe(app.buttons["today.person-picker"], "everyone.picker")
        probe(app.staticTexts["today.everyone-headline"], "everyone.headline")
        note("Taken buttons on first screen: \(count(app.buttons.matching(identifier: "today.dose.take")))")
        note("Status menus on first screen: \(count(app.buttons.matching(identifier: "today.dose.status")))")

        // How far down is the first dose?
        let take = app.buttons["today.dose.take"].firstMatch
        probe(take, "everyone.first-take")

        app.swipeUp()
        shot(app, "02-today-everyone-scrolled")
        note("Taken buttons after one scroll: \(count(app.buttons.matching(identifier: "today.dose.take")))")
        app.swipeUp()
        shot(app, "03-today-everyone-scrolled-2")
        app.swipeUp()
        shot(app, "04-today-everyone-bottom")
        for _ in 0..<4 { app.swipeDown() }

        // Tick every visible Taken button, counting taps.
        var taps = 0
        for _ in 0..<12 {
            let b = app.buttons["today.dose.take"].firstMatch
            guard b.exists, b.isHittable else { break }
            b.tap()
            taps += 1
            usleep(500_000)
            if taps == 1 { shot(app, "05-after-first-taken") }
        }
        note("Taps to clear the visible doses one by one: \(taps)")
        shot(app, "06-after-all-visible-taken")
        probe(app.buttons["today.undo"], "everyone.undo-banner-after-dose")

        // Change a recorded dose through its status menu.
        let status = app.buttons["today.dose.status"].firstMatch
        probe(status, "everyone.status-menu")
        if status.exists, status.isHittable {
            status.tap()
            sleep(1)
            shot(app, "07-dose-status-menu")
            app.tapAwayFromMenu()
        }

        // Swipe a recorded dose.
        if status.exists {
            status.swipeLeft()
            sleep(1)
            shot(app, "08-dose-swipe-actions")
            status.swipeRight()
        }

        // Task / bill tick-off and the undo bar.
        app.swipeUp()
        sleep(1)
        shot(app, "09-today-sections")
        let taskDone = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'done' OR label CONTAINS[c] 'complete'")).firstMatch
        probe(taskDone, "everyone.task-complete-control")
        if taskDone.exists, taskDone.isHittable {
            taskDone.tap()
            sleep(1)
            shot(app, "10-after-task-done-undo-bar")
            probe(app.buttons["today.undo"], "everyone.undo-after-task")
        }
    }

    // MARK: - Daily loop: one person

    func testExperiencedPersonDay() {
        let app = launchSeeded()
        selectPersonOnToday(app, named: "Eleanor Wallner")
        sleep(1)
        shot(app, "20-today-mom-first")
        note("Taken buttons on Mom's first screen: \(count(app.buttons.matching(identifier: "today.dose.take")))")
        probe(app.buttons["today.dose.take"].firstMatch, "mom.first-take")
        for action in ["medications", "tasks", "bills", "medical", "notes", "contacts"] {
            probe(app.buttons["today.quick.\(action)"], "mom.quick.\(action)")
        }
        app.swipeUp()
        shot(app, "21-today-mom-scrolled")
        app.swipeUp()
        shot(app, "22-today-mom-scrolled-2")

        // Running low row: is it tappable?
        let low = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'days left' OR label CONTAINS[c] 'None left' OR label CONTAINS[c] 'Last dose'")).firstMatch
        probe(low, "mom.running-low-row")
        if low.exists, low.isHittable {
            low.tap()
            sleep(1)
            shot(app, "23-after-tap-running-low-row")
        }
    }

    // MARK: - Deeper features from the person hub

    func testExperiencedHubAndEditors() {
        let app = launchSeeded()
        selectPersonOnToday(app, named: "Eleanor Wallner")
        let full = app.buttons["today.medications"]
        scrollUntilHittable(full, in: app)
        full.tap()
        sleep(1)
        shot(app, "30-hub-top")
        app.swipeUp()
        shot(app, "31-hub-scrolled")

        // Edit an existing medication in place.
        let med = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'person-detail.medication.'")).firstMatch
        scrollUpTo(med, app)
        probe(med, "hub.medication-row")
        if med.exists, med.isHittable {
            med.tap()
            sleep(1)
            shot(app, "32-med-editor-existing")
            app.swipeUp()
            shot(app, "33-med-editor-scrolled")
            app.swipeUp()
            shot(app, "34-med-editor-scrolled-2")
            probe(app.buttons["medication-editor.save"], "med-editor.save")
            probe(app.buttons["Cancel"], "med-editor.cancel")
            app.buttons["Cancel"].firstMatch.tap()
            sleep(1)
        }

        // Add a second medication with a weekly schedule and refill tracking.
        for _ in 0..<3 { app.swipeDown() }
        let add = app.buttons["person-detail.add-medication"]
        scrollUntilHittable(add, in: app)
        if add.exists {
            add.tap()
            let name = app.textFields["Medication name"]
            if name.waitForExistence(timeout: 5) {
                name.tap()
                name.typeText("Alendronate")
                shot(app, "35-new-med-typed")
                let time = app.datePickers.firstMatch
                probe(time, "new-med.time-picker")
                let mon = app.buttons["medication-editor.weekday.2"]
                scrollUntilHittable(mon, in: app, attempts: 3)
                probe(mon, "new-med.weekday-mon")
                shot(app, "36-new-med-schedule")
                let track = app.switches["Track refills"]
                scrollUntilHittable(track, in: app, attempts: 3)
                probe(track, "new-med.track-refills")
                if track.exists, track.isHittable {
                    track.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
                    sleep(1)
                    shot(app, "37-new-med-refills-on")
                }
                app.buttons["Cancel"].firstMatch.tap()
            }
        }
    }

    func testExperiencedVitalsRepeatEntry() {
        let app = launchSeeded()
        selectPersonOnToday(app, named: "Eleanor Wallner")
        let medical = app.buttons["today.quick.medical"]
        scrollUntilHittable(medical, in: app)
        probe(medical, "vitals.medical-chip")
        medical.tap()
        sleep(1)
        shot(app, "40-medical-screen")
        let vitals = app.buttons["medical.vitals"]
        probe(vitals, "vitals.entry")
        if vitals.exists { vitals.tap() } else { app.buttons["Vitals"].firstMatch.tap() }
        sleep(1)
        shot(app, "41-vitals-list")
        probe(app.buttons["Add reading"], "vitals.add")
        app.buttons["Add reading"].firstMatch.tap()
        let sys = app.textFields["Systolic"]
        if sys.waitForExistence(timeout: 5) {
            shot(app, "42-vitals-sheet-empty")
            probe(sys, "vitals.systolic-field")
            note("Keyboard up on open (before any tap): \(app.keyboards.count > 0)")
            sys.tap()
            sys.typeText("128")
            let dia = app.textFields["Diastolic"]
            dia.tap()
            dia.typeText("82")
            shot(app, "43-vitals-sheet-typed")
            probe(app.buttons["Save"], "vitals.save")
            app.buttons["Save"].tap()
            sleep(1)
            shot(app, "44-vitals-after-save")
        }
        // Second reading straight away: taps and what the sheet remembers.
        app.buttons["Add reading"].firstMatch.tap()
        sleep(1)
        shot(app, "45-vitals-second-sheet")
        app.buttons["Cancel"].firstMatch.tap()
        sleep(1)

        // Another kind of reading via the menu.
        let picker = app.buttons["Reading"].firstMatch
        probe(picker, "vitals.kind-picker")
        if picker.exists {
            picker.tap()
            sleep(1)
            shot(app, "46-vitals-kind-menu")
        }
    }

    func testExperiencedTasksAndRecurrence() {
        let app = launchSeeded()
        selectPersonOnToday(app, named: "Eleanor Wallner")
        let tasks = app.buttons["today.quick.tasks"]
        scrollUntilHittable(tasks, in: app)
        tasks.tap()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))
        sleep(1)
        shot(app, "50-tasks-list")
        probe(app.segmentedControls["tasks.scope"], "tasks.scope")
        app.swipeUp()
        shot(app, "51-tasks-scrolled")
        app.swipeDown()

        app.buttons["tasks.add"].tap()
        let title = app.textFields["task-editor.title"]
        if title.waitForExistence(timeout: 5) {
            shot(app, "52-task-editor-empty")
            title.tap()
            title.typeText("Order hearing aid batteries")
            shot(app, "53-task-editor-typed")
            let assignee = app.buttons["task-editor.assignee"]
            scrollUntilHittable(assignee, in: app, attempts: 3)
            probe(assignee, "task.assignee")
            let repeatPicker = app.buttons["task-editor.repeat"]
            scrollUntilHittable(repeatPicker, in: app, attempts: 3)
            probe(repeatPicker, "task.repeat")
            shot(app, "54-task-editor-scrolled")
            app.buttons["Cancel"].firstMatch.tap()
        }
    }

    func testExperiencedBillsNotesTimelineSearch() {
        let app = launchSeeded()
        selectPersonOnToday(app, named: "Eleanor Wallner")

        let bills = app.buttons["today.quick.bills"]
        scrollUntilHittable(bills, in: app)
        bills.tap()
        sleep(1)
        shot(app, "60-bills")
        app.swipeUp()
        shot(app, "61-bills-scrolled")
        back(app)

        let notes = app.buttons["today.quick.notes"]
        scrollUntilHittable(notes, in: app)
        notes.tap()
        sleep(1)
        shot(app, "62-notes")
        back(app)

        // Timeline through Medical.
        let medical = app.buttons["today.quick.medical"]
        scrollUntilHittable(medical, in: app)
        medical.tap()
        sleep(1)
        let timeline = app.buttons["medical.timeline"]
        probe(timeline, "medical.timeline")
        if timeline.exists {
            timeline.tap()
            sleep(1)
            shot(app, "63-timeline")
            app.swipeUp()
            shot(app, "64-timeline-scrolled")
            probe(app.searchFields.firstMatch, "timeline.search-field")
        }

        // Cross-record search on the Care tab.
        app.tabBars.buttons["Care"].tap()
        sleep(1)
        shot(app, "65-care-tab")
        let search = app.searchFields.firstMatch
        probe(search, "care.search-field")
        if search.exists {
            search.tap()
            search.typeText("hearing")
            sleep(2)
            shot(app, "66-care-search-hearing")
            note("Search hits for 'hearing' (cells): \(app.cells.count)")
        }
    }

    func testExperiencedEmergencyExportAndSettings() {
        let app = launchSeeded()
        selectPersonOnToday(app, named: "Eleanor Wallner")
        let card = app.buttons["today.emergency-card"]
        scrollUntilHittable(card, in: app)
        probe(card, "card.entry")
        if card.exists {
            card.tap()
            sleep(1)
            shot(app, "70-emergency-card")
            app.swipeUp()
            shot(app, "71-emergency-card-scrolled")
            app.swipeUp()
            shot(app, "72-emergency-card-scrolled-2")
            probe(app.buttons["Share"].firstMatch, "card.share")
            let share = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'share' OR label CONTAINS[c] 'export' OR label CONTAINS[c] 'print'")).firstMatch
            probe(share, "card.share-or-export")
            if share.exists, share.isHittable {
                share.tap()
                sleep(2)
                shot(app, "73-share-sheet")
            }
        }

        app.terminate()
        let relaunch = launchSeeded()
        relaunch.tabBars.buttons["Settings"].tap()
        sleep(1)
        shot(relaunch, "74-settings-top")
        relaunch.swipeUp()
        shot(relaunch, "75-settings-scrolled")
        relaunch.swipeUp()
        shot(relaunch, "76-settings-scrolled-2")
        relaunch.swipeUp()
        shot(relaunch, "77-settings-bottom")
        relaunch.tabBars.buttons["Sharing"].tap()
        sleep(1)
        shot(relaunch, "78-sharing-tab")
    }

    // MARK: - Return visit: state survives a relaunch

    func testExperiencedRelaunchKeepsDoseAndScope() {
        let app = launchSeeded()
        selectPersonOnToday(app, named: "Eleanor Wallner")
        sleep(1)
        let before = count(app.buttons.matching(identifier: "today.dose.take"))
        let take = app.buttons["today.dose.take"].firstMatch
        if take.exists, take.isHittable { take.tap() }
        sleep(1)
        let after = count(app.buttons.matching(identifier: "today.dose.take"))
        note("Taken buttons before/after one tap: \(before)/\(after)")
        shot(app, "80-before-relaunch")
        app.terminate()

        let again = XCUIApplication()
        // Same store, no wipe, no reseed.
        again.launchArguments += ["-uitest-reset", "NO"]
        again.launch()
        _ = again.navigationBars["Today"].waitForExistence(timeout: 20)
        sleep(1)
        shot(again, "81-after-relaunch")
        probe(again.buttons["today.person-picker"], "relaunch.picker")
        note("Taken buttons after relaunch: \(count(again.buttons.matching(identifier: "today.dose.take")))")
        note("Everyone headline present after relaunch: \(again.staticTexts["today.everyone-headline"].exists)")
    }

    // MARK: - Helpers

    private func scrollUpTo(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
    }
}

private extension XCUIApplication {
    /// Dismisses a context menu by tapping the top-left corner, away from it.
    func tapAwayFromMenu() {
        coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.12)).tap()
    }
}
