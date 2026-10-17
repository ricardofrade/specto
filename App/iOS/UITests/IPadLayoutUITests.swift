import XCTest

/// M3 on iPad: sidebar, the Watch band (portrait) with comments, and the side panel (landscape).
/// Needs `TEST_RUNNER_PIPED_URL`; skipped on iPhone and without it.
final class IPadLayoutUITests: XCTestCase {
    @MainActor
    func testSidebarBandAndSidePanel() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad only") }
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"]
        app.launch()
        app.buttons["Add Instance"].firstMatch.tap()      // Feed's empty state → Instances screen.
        XCTAssertTrue(app.navigationBars["Instances"].waitForExistence(timeout: 5))
        app.buttons["Add Instance"].firstMatch.tap()
        let field = app.textFields["instance.url"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(piped)
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Instance added"].waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
        app.buttons["Home"].firstMatch.tap()
        let list = app.scrollViews["feed.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 45))
        attach(app, "ipad-feed")

        list.buttons.firstMatch.tap()
        let surface = app.otherElements["watch.surface"]
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "value BEGINSWITH 'playing '"),
                                                          evaluatedWith: surface)], timeout: 45), .completed)
        // Portrait iPad: the band below the video, with tabs.
        let comments = app.buttons["Comments"]
        XCTAssertTrue(comments.waitForExistence(timeout: 10), "No tabbed band in portrait")
        comments.tap()
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 30), "Comments didn't load")
        attach(app, "ipad-band-comments")

        // Landscape: side panel beside the video, playback uninterrupted.
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        XCTAssertTrue((surface.value as? String ?? "").hasPrefix("playing "))
        attach(app, "ipad-side-panel")
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
