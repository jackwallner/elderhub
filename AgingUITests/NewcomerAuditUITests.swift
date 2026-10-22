import XCTest

/// Persona audit walk: a first-time user who knows none of the app's terms and
/// wants one useful result at once. Captures a screenshot at every step and a
/// text log of control sizes, and asserts almost nothing, so a surprising
/// screen is photographed rather than aborting the walk.
@MainActor
final class NewcomerAuditUITests: XCTestCase {

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

    /// Records whether a control exists, is hittable and how big it is.
    private func probe(_ element: XCUIElement, _ name: String) {
        guard element.exists else {
            log.append("\(name): MISSING")
            return
        }
        let f = element.frame
        log.append("\(name): \(Int(f.width))x\(Int(f.height)) at (\(Int(f.minX)),\(Int(f.minY))) hittable=\(element.isHittable) enabled=\(element.isEnabled)")
    }

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-reset", "YES", "-uitest-wipe-store", "YES"]
        app.launch()
        return app
    }

    // MARK: - First run

    func testNewcomerFirstRunToFirstDose() {
        let app = launchFresh()

        let start = app.buttons["Start a care record"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        shot(app, "01-fork")
        probe(start, "fork.start")
        probe(app.buttons["I have an invitation"], "fork.invitation")
        probe(app.buttons["Keep track of myself"], "fork.solo")
        start.tap()

        let nameField = app.textFields["Their name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        shot(app, "02-name-empty")
        probe(app.buttons["Continue"], "name.continue-before-typing")
        nameField.tap()
        nameField.typeText("Mom")
        shot(app, "03-name-typed-keyboard-up")
        probe(app.buttons["Continue"], "name.continue-keyboard-up")
        probe(app.switches["onboarding.attestation"], "name.attestation-keyboard-up")

        // What a newcomer sees if they try Continue without the permission toggle.
        let attestation = app.switches["onboarding.attestation"]
        if attestation.exists, (attestation.value as? String) != "1" {
            let control = attestation.switches.firstMatch
            if control.exists { control.tap() } else { attestation.tap() }
        }
        shot(app, "04-name-attested")
        probe(app.buttons["Continue"], "name.continue-after-attest")
        app.buttons["Continue"].tap()

        // Sign in
        let notNow = app.buttons["Not now"]
        XCTAssertTrue(notNow.waitForExistence(timeout: 5))
        shot(app, "05-signin")
        probe(notNow, "signin.not-now")
        probe(app.buttons["onboarding.back"], "signin.back")
        notNow.tap()

        // Details flow, step by step.
        let skip = app.buttons["onboarding.details.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        shot(app, "06-details-1-birthdate")
        probe(skip, "details.skip")
        probe(app.buttons["onboarding.details.continue"], "details.continue")
        probe(app.buttons["onboarding.details.finish-later"], "details.finish-later")

        // Step 1: birth date
        let dobToggle = app.switches["I know the date of birth"]
        if dobToggle.exists {
            dobToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            shot(app, "07-details-1-birthdate-wheel")
        }
        app.buttons["onboarding.details.continue"].tap()

        // Step 2: allergies
        shot(app, "08-details-2-allergies")
        let allergy = app.textFields.firstMatch
        if allergy.waitForExistence(timeout: 3) {
            allergy.tap()
            allergy.typeText("Penicillin")
            shot(app, "09-details-2-allergies-typed-keyboard")
            probe(app.buttons["onboarding.details.continue"], "allergies.continue-keyboard-up")
            probe(app.buttons["onboarding.details.skip"], "allergies.skip-keyboard-up")
        }
        // Continue (without tapping the plus) to see whether the typed draft is kept.
        if app.buttons["onboarding.details.continue"].isHittable {
            app.buttons["onboarding.details.continue"].tap()
        } else {
            app.swipeDown()
            app.buttons["onboarding.details.continue"].tap()
        }

        // Step 3: conditions
        shot(app, "10-details-3-conditions")
        app.buttons["onboarding.details.skip"].tap()

        // Step 4: contact
        shot(app, "11-details-4-contact")
        app.buttons["onboarding.details.skip"].tap()

        // Step 5: medication
        shot(app, "12-details-5-medication")
        let addMed = app.buttons["Add a medication"]
        XCTAssertTrue(addMed.waitForExistence(timeout: 5))
        probe(addMed, "details.add-medication")
        addMed.tap()

        let medName = app.textFields["Medication name"]
        XCTAssertTrue(medName.waitForExistence(timeout: 5))
        shot(app, "13-med-sheet-empty")
        probe(app.buttons["medication-editor.save"], "med.save-before-typing")
        medName.tap()
        medName.typeText("Metformin")
        shot(app, "14-med-sheet-typed-keyboard")
        probe(app.buttons["medication-editor.save"], "med.save-after-typing")
        let save = app.buttons["medication-editor.save"]
        if save.exists { save.tap() }

        // Back on the step: does it confirm the addition?
        sleep(1)
        shot(app, "15-details-5-after-med-saved")
        app.buttons["onboarding.details.continue"].tap()

        // Step 6: providers
        shot(app, "16-details-6-providers")
        app.buttons["onboarding.details.skip"].tap()

        // Step 7: reminders
        shot(app, "17-details-7-reminders")
        app.buttons["onboarding.details.skip"].tap()

        // Step 8: family
        shot(app, "18-details-8-family")
        probe(app.buttons["onboarding.details.skip"], "family.finish-without")
        app.buttons["onboarding.details.skip"].tap()

        // Feature overview
        let open = app.buttons["onboarding.open-record"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        shot(app, "19-overview")
        app.swipeUp()
        shot(app, "20-overview-scrolled")
        probe(open, "overview.open-record")
        open.tap()

        // Today
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        sleep(1)
        shot(app, "21-today-first-view")
        probe(app.buttons["today.dose.take"], "today.dose-take")
        probe(app.buttons["setup-card.expand"], "today.setup-expand")
        probe(app.buttons["today.medications"], "today.full-record")

        let take = app.buttons["today.dose.take"]
        if take.exists {
            take.tap()
            sleep(1)
            shot(app, "22-today-after-taken")
        }
        app.swipeUp()
        shot(app, "23-today-scrolled")
        app.swipeDown()
        app.swipeDown()

        // Tabs
        app.tabBars.buttons["Care"].tap()
        sleep(1)
        shot(app, "24-care-tab")
        app.tabBars.buttons["Sharing"].tap()
        sleep(1)
        shot(app, "25-sharing-tab")
        app.tabBars.buttons["Settings"].tap()
        sleep(1)
        shot(app, "26-settings-tab")
    }

    // MARK: - Return visit and hub

    func testNewcomerHubAndEmptyToday() {
        let app = launchFresh()
        completeOnboarding(app, name: "Dad")
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        sleep(1)
        shot(app, "30-today-empty-record")
        probe(app.buttons["setup-card.expand"], "empty.setup-expand")

        let card = app.otherElements["today.setup-card"]
        probe(card, "empty.setup-card")
        if app.buttons["setup-card.expand"].exists {
            app.buttons["setup-card.expand"].tap()
            shot(app, "31-today-setup-expanded")
        }

        app.swipeUp()
        shot(app, "32-today-empty-scrolled")
        app.swipeDown()

        let full = app.buttons["today.medications"]
        scrollUntilHittable(full, in: app)
        if full.exists {
            full.tap()
            sleep(1)
            shot(app, "33-person-hub")
            app.swipeUp()
            shot(app, "34-person-hub-scrolled")
            app.swipeUp()
            shot(app, "35-person-hub-scrolled-2")
        }
    }

    func testNewcomerEmergencyCardEmpty() {
        let app = launchFresh()
        completeOnboarding(app, name: "Dad")
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        let card = app.buttons["today.emergency-card"]
        scrollUntilHittable(card, in: app)
        if card.exists {
            card.tap()
            sleep(1)
            shot(app, "40-emergency-card-empty")
        }
    }
}
