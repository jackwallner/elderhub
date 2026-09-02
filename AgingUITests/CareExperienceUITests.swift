import XCTest

/// The fixes with a visible surface, driven through the real app.
///
/// Each of these was a dead end rather than a wrong pixel: a control that did
/// nothing visible, a choice put to somebody with no information behind it, or
/// an action with no route back. That is the kind of thing a render test does
/// not catch, so they are asserted here on the elements a person would actually
/// reach for.
@MainActor
final class CareExperienceUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Seeded rather than onboarded: these need a record with medications, a
    /// task and a primary contact already in it, which is what `-seedDemo`
    /// builds. Wiped first, because `seedIfEmpty` does nothing on a pool device
    /// still holding last week's store.
    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-wipe-store", "YES", "-seedDemo", "YES"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15))
        // `-seedDemo` seeds both Mom and Dad, so Today opens on the aggregate.
        selectPersonOnToday(app, named: "Eleanor Wallner")
        return app
    }

    // MARK: The reported bug

    /// The primary contact was sorted to the top of the emergency card and
    /// marked nowhere. Order is not a signal a stranger can read: somebody
    /// holding this page has no reason to think the list is ordered at all.
    func testTheEmergencyCardSaysWhoToCallFirst() throws {
        let app = launchSeeded()

        let card = app.buttons["today.emergency-card"]
        scrollUntilHittable(card, in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        XCTAssertTrue(app.navigationBars["Emergency Card"].waitForExistence(timeout: 5))

        let callFirst = app.staticTexts["CALL FIRST"]
        scrollUntilHittable(callFirst, in: app)
        XCTAssertTrue(
            callFirst.waitForExistence(timeout: 5),
            "The primary contact is not marked on the card, so the page does not say who to ring"
        )

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "emergency-card-call-first"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: Dead ends

    /// Settings is where people look for a backup, and the Account section made
    /// a statement and offered nothing. The only sign-in in the app was behind
    /// the Sharing tab, which a solo caregiver has no reason to open.
    func testSettingsOffersSignInWhenSignedOut() throws {
        let app = launchSeeded()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let signIn = app.buttons["settings.sign-in"]
        scrollUntilHittable(signIn, in: app)
        XCTAssertTrue(signIn.exists, "Settings offered no way to back the record up")

        signIn.tap()
        // The destination is framed as a backup, not as sharing.
        XCTAssertTrue(
            app.staticTexts["Keep your list safe"].waitForExistence(timeout: 5),
            "Sign in from Settings did not reach the back-up screen"
        )
    }

    /// No rating request and no feedback route existed anywhere. Both are now a
    /// deliberate tap away, and a deliberate tap is never gated by the passive
    /// prompt's eligibility rules.
    func testSettingsCanAskForARatingOnDemand() throws {
        let app = launchSeeded()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let rate = app.buttons["settings.rate"]
        scrollUntilHittable(rate, in: app)
        XCTAssertTrue(rate.exists, "Settings had no way to rate the app")
        XCTAssertTrue(app.buttons["settings.contact"].exists, "Settings had no way to report a problem")

        rate.tap()

        // The fork is the point: somebody unhappy gets a route that is not a
        // one-star review.
        XCTAssertTrue(app.buttons["review.rate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["review.feedback"].exists)

        app.buttons["Not now"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    // MARK: No way back

    /// Marking a task done on Today removes the row from the section that built
    /// it, so before the banner the only route back was another tab, a hidden
    /// section and a second tap.
    func testTickingATaskOffOnTodayCanBeUndone() throws {
        let app = launchSeeded()

        let tick = app.buttons["Mark Replace hearing aid batteries done"]
        scrollUntilHittable(tick, in: app)
        XCTAssertTrue(tick.waitForExistence(timeout: 5), "The seeded task is not on Today")
        tick.tap()

        let undo = app.buttons["today.undo"]
        XCTAssertTrue(
            undo.waitForExistence(timeout: 5),
            "Ticking a task off offered no undo, and the row is already gone"
        )
        undo.tap()

        let back = app.buttons["Mark Replace hearing aid batteries done"]
        scrollUntilHittable(back, in: app)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Undo did not put the task back")
    }

    // MARK: Accessibility

    /// The dose button is the most-tapped control in the app and was announced
    /// as a bare "Taken", so a list of doses gave a column of identical buttons
    /// and VoiceOver could not say which drug was about to be recorded.
    func testTheDoseButtonNamesItsMedication() throws {
        let app = launchSeeded()

        let named = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Mark Lisinopril at")
        ).firstMatch
        scrollUntilHittable(named, in: app)
        XCTAssertTrue(
            named.waitForExistence(timeout: 5),
            "The dose button did not name the medication it records"
        )
    }
}
