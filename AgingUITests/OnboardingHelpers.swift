import XCTest

/// Getting through first launch, in one place.
///
/// Six test bundles each open the app on a clean store and need a record before
/// they can test anything, and every one of them had its own inline copy of the
/// steps. Adding the skippable details flow between naming the person and the
/// feature overview broke all six identically, which is the argument for this
/// file existing.
extension XCUIApplication {
    /// True on the unfolded Duo only. Folded, the strip is still in the tree
    /// (invisible and accessibility hidden, yet found by queries), so it counts
    /// only when the system tab bar is not there.
    var hasPaneTabStrip: Bool {
        tabBars.count == 0 && buttons["pane-tab.today"].exists
    }
}

extension XCTestCase {

    /// Walks the fork, the name, the sign-in skip, every detail step and the
    /// feature overview, and returns once the Today tab is up.
    ///
    /// The name comes *before* the sign-in step, which is the order 1.0.1 was
    /// rejected for getting backwards: nothing may ask for a name on the screen
    /// after Sign in with Apple (App Review 4.0).
    ///
    /// Every step is guarded: several callers launch onto a store that already
    /// has a person, where none of this appears.
    @MainActor
    func completeOnboarding(_ app: XCUIApplication, name: String = "Eleanor Wallner") {
        let supporter = app.buttons["Start a care record"]
        if supporter.waitForExistence(timeout: 5) {
            supporter.tap()
        }

        let nameField = app.textFields["Their name"]
        if nameField.waitForExistence(timeout: 5) {
            nameField.tap()
            nameField.typeText(name)
            attest(app)
            app.buttons["Continue"].tap()
        }

        let notNow = app.buttons["Not now"]
        if notNow.waitForExistence(timeout: 5) {
            notNow.tap()
        }

        skipTheDetailsFlow(app)

        let openRecord = app.buttons["onboarding.open-record"]
        if openRecord.waitForExistence(timeout: 5) {
            openRecord.tap()
        }
    }

    /// Turns on the surrogate attestation, which gates Continue on the
    /// supporter path. It used to appear only for someone already signed in,
    /// which after the reorder would be nobody: this step now runs before the
    /// account does.
    @MainActor
    func attest(_ app: XCUIApplication) {
        let row = app.switches["onboarding.attestation"]
        guard row.waitForExistence(timeout: 3) else { return }
        guard (row.value as? String) != "1" else { return }

        // The identifier is on the whole row, whose centre is the sentence, not
        // the control. A SwiftUI `Toggle` outside a `List` only flips when the
        // switch itself is hit, so tapping the row taps a piece of text and
        // leaves Continue disabled.
        let control = row.switches.firstMatch
        if control.exists { control.tap() } else { row.tap() }
        XCTAssertEqual(row.value as? String, "1", "The attestation toggle did not flip")
    }

    /// Skips every question in `OnboardingDetailsFlow`.
    ///
    /// Capped rather than `while`: a Skip that stops advancing would otherwise
    /// hang the whole bundle instead of failing the one test.
    @MainActor
    func skipTheDetailsFlow(_ app: XCUIApplication) {
        let skip = app.buttons["onboarding.details.skip"]
        guard skip.waitForExistence(timeout: 5) else { return }
        for _ in 0..<12 where skip.exists {
            skip.tap()
        }
    }
}

extension XCTestCase {
    /// Scrolls until the element can be tapped.
    ///
    /// Needed more often since the setup checklist moved to the top of Today:
    /// on a record with nothing in it the two big cards at the bottom start
    /// below the fold, and a `List` does not render a row it has not scrolled
    /// to, so `exists` is false rather than merely off screen.
    @MainActor
    func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 8, trailing: Bool = false) {
        for _ in 0..<attempts where !element.isHittable {
            paneSwipe(app, .up, trailing: trailing)
        }
    }

    /// A vertical drag inside one pane. Unfolded on the Duo, the middle of the
    /// app is the fold between the panes, so a drag there scrolls neither:
    /// Today and its tab strip lead, Care (`trailing`) follows. The app's own
    /// frame is the rotated portrait one there (669 by 951 on a 951 by 669
    /// display), so a drag measured against it starts below the screen and
    /// scrolls nothing; the pane's list reports its true frame. Folded it is
    /// `QA.swipe` on the list that is showing.
    @MainActor
    func paneSwipe(_ app: XCUIApplication, _ direction: QA.Direction, trailing: Bool = false) {
        let lists = (app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex)
            .filter { $0.frame.height > 200 && $0.frame.width > 200 }
        if app.hasPaneTabStrip, lists.count > 1 {
            let pane = trailing ? lists.max { $0.frame.minX < $1.frame.minX } : lists.min { $0.frame.minX < $1.frame.minX }
            if let pane {
                QA.swipe(pane, direction)
                return
            }
        }
        // Drag the list that is showing, not the whole app: on the Duo's
        // window the app frame is not the screen the user sees.
        let list = app.collectionViews.allElementsBoundByIndex.first { $0.isHittable }
            ?? app.tables.allElementsBoundByIndex.first { $0.isHittable }
        QA.swipe(list ?? app, direction)
    }

    /// Scope the Today tab to one person.
    ///
    /// `-seedDemo` puts both Mom and Dad on the store, and Today opens on the
    /// aggregate whenever a phone is tracking more than one person, so the
    /// per-person chips and cards are not on screen until somebody is picked.
    /// A no-op on a single-person store, where the picker does not exist at
    /// all: the tests that walk through onboarding are testing exactly that
    /// screen and must not be made to tap something a real solo caregiver
    /// never sees.
    @MainActor
    func selectPersonOnToday(_ app: XCUIApplication, named name: String) {
        let picker = app.buttons["today.person-picker"]
        guard picker.waitForExistence(timeout: 5) else { return }
        picker.tap()
        let entry = app.buttons["today.person-option.\(name)"]
        if entry.waitForExistence(timeout: 3) {
            entry.tap()
        }
    }
}
