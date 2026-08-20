import XCTest

/// Getting through first launch, in one place.
///
/// Six test bundles each open the app on a clean store and need a record before
/// they can test anything, and every one of them had its own inline copy of the
/// steps. Adding the skippable details flow between naming the person and the
/// feature overview broke all six identically, which is the argument for this
/// file existing.
extension XCTestCase {

    /// Walks the fork, the sign-in skip, the name, every detail step and the
    /// feature overview, and returns once the Today tab is up.
    ///
    /// Every step is guarded: several callers launch onto a store that already
    /// has a person, where none of this appears.
    @MainActor
    func completeOnboarding(_ app: XCUIApplication, name: String = "Eleanor Wallner") {
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
            nameField.typeText(name)
            app.buttons["Continue"].tap()
        }

        skipTheDetailsFlow(app)

        let openRecord = app.buttons["onboarding.open-record"]
        if openRecord.waitForExistence(timeout: 5) {
            openRecord.tap()
        }
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
    func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 8) {
        for _ in 0..<attempts where !element.isHittable {
            app.swipeUp()
        }
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
