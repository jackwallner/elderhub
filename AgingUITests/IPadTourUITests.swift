import XCTest

/// iPad screenshots of every main surface in portrait and landscape, for a
/// person to look at. Skips itself on iPhone. `gh-sim` cannot rotate a
/// simulator, so the rotation happens here and the frames come back as the
/// run's attachments (`gh-sim test --scheme AgingUITests --only
/// AgingUITests/IPadTourUITests --device "iPad Pro 13-inch (M5)"`).
@MainActor
final class IPadTourUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
    }

    private func launch(_ arguments: [String], landscape: Bool) -> XCUIApplication {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launch()
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        return app
    }

    private func seeded(_ route: String, landscape: Bool) -> XCUIApplication {
        launch(["-uitest-family", "YES", "-seedDemo", "YES", "-DuoTour", "-DuoScreen", route], landscape: landscape)
    }

    /// The window screenshot is the whole app, but in landscape the simulator
    /// hands it back as a portrait buffer turned a quarter clockwise (the app
    /// and screen screenshots clip it). The `-land` frames are turned back
    /// upright after the run (`sips -r 270`).
    private func attach(_ app: XCUIApplication, _ name: String, _ landscape: Bool) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "\(name)-\(landscape ? "land" : "port")"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func orientations(_ body: (Bool) -> Void) {
        for landscape in [false, true] { body(landscape) }
    }

    private func tourRoute(_ name: String, _ route: String) {
        orientations { landscape in
            let app = seeded(route, landscape: landscape)
            sleep(9)
            attach(app, name, landscape)
            app.terminate()
        }
    }

    func testToday() { tourRoute("today", "today") }
    func testCare() { tourRoute("care", "care") }
    func testHub() { tourRoute("hub", "care+mom") }
    func testEmergencyCard() { tourRoute("card", "care+mom.card") }
    func testTasks() { tourRoute("tasks", "care+mom.tasks") }
    func testBills() { tourRoute("bills", "care+mom.bills") }
    func testVisits() { tourRoute("visits", "care+mom.visits") }
    func testTimeline() { tourRoute("timeline", "care+mom.timeline") }
    func testSharing() { tourRoute("sharing", "sharing") }
    func testSettings() { tourRoute("settings", "settings") }

    func testOnboarding() {
        orientations { landscape in
            let app = launch(["-uitest-reset", "YES", "-uitest-wipe-store", "YES"], landscape: landscape)
            let supporter = app.buttons["Start a care record"]
            _ = supporter.waitForExistence(timeout: 20)
            sleep(1)
            attach(app, "onboarding-1-path", landscape)
            supporter.tap()

            let nameField = app.textFields["Their name"]
            if nameField.waitForExistence(timeout: 8) {
                nameField.tap()
                nameField.typeText("Eleanor Wallner")
                attest(app)
                attach(app, "onboarding-2-name", landscape)
                app.buttons["Continue"].tap()
            }

            let notNow = app.buttons["Not now"]
            if notNow.waitForExistence(timeout: 8) {
                attach(app, "onboarding-3-signin", landscape)
                notNow.tap()
            }

            let skip = app.buttons["onboarding.details.skip"]
            if skip.waitForExistence(timeout: 8) {
                var step = 4
                for _ in 0..<12 where skip.exists {
                    attach(app, "onboarding-\(step)-details", landscape)
                    step += 1
                    skip.tap()
                    sleep(1)
                }
            }

            let openRecord = app.buttons["onboarding.open-record"]
            if openRecord.waitForExistence(timeout: 8) {
                attach(app, "onboarding-9-overview", landscape)
            }
            app.terminate()
        }
    }

    func testPaywall() {
        orientations { landscape in
            let app = launch(["-uitest-reset", "YES", "-uitest-wipe-store", "YES"], landscape: landscape)
            completeOnboarding(app)
            _ = app.navigationBars["Today"].waitForExistence(timeout: 15)
            app.buttons["Care"].firstMatch.tap()
            sleep(2)
            app.buttons["Add person"].firstMatch.tap()
            _ = app.buttons["paywall.plan.com.jackwallner.aging.pro.monthly"].waitForExistence(timeout: 20)
            sleep(2)
            attach(app, "paywall", landscape)
            app.terminate()
        }
    }
}
