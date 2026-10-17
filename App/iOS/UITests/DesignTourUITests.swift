import XCTest

/// Screenshots of the main screens against a real instance, for design review. Run it in light
/// and in dark appearance (`xcrun simctl ui <device> appearance dark`). Attachments are kept.
final class DesignTourUITests: XCTestCase {
    @MainActor
    func testTour() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped,
                               "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"]
        app.launch()
        let list = app.scrollViews["feed.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 45))
        sleep(3)
        shot(app, "1-home")

        list.buttons.firstMatch.tap()
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45))
        sleep(8)
        shot(app, "2-watch")
        app.swipeUp()
        sleep(1)
        shot(app, "3-watch-scrolled")

        app.buttons["watch.close"].tap()
        sleep(2)
        shot(app, "4-home-after")
        list.swipeUp()
        sleep(1)
        shot(app, "5-home-scrolled")
    }

    /// The newer screens: Explore, the player's floating controls and settings menu, the Save
    /// sheet and Library → Playlists.
    @MainActor
    func testTourOfNewerScreens() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)"]
        app.launch()
        let trending = app.descendants(matching: .any)["feed.trending"].firstMatch
        XCTAssertTrue(trending.waitForExistence(timeout: 45))
        sleep(3)
        shot(app, "6-explore")

        trending.tap()
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45))
        _ = app.playerControl("watch.settings")
        shot(app, "7-player-controls")
        app.playerControl("watch.settings").tap()
        XCTAssertTrue(app.buttons["Playback Speed"].waitForExistence(timeout: 5))
        shot(app, "8-player-settings")
        app.buttons["Playback Speed"].tap()
        sleep(1)
        shot(app, "9-player-speed")
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()   // Dismiss the menu.
        sleep(1)

        app.buttons["watch.save"].tap()
        XCTAssertTrue(app.buttons["save.new"].waitForExistence(timeout: 5))
        shot(app, "10-save-sheet")
        app.buttons.matching(identifier: "save.playlist").firstMatch.tap()   // Watch Later.
        app.buttons["Done"].tap()
        app.buttons["watch.close"].tap()
        app.buttons["Library"].firstMatch.tap()
        XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 5))
        app.buttons["library.playlists"].tap()
        XCTAssertTrue(app.buttons["playlists.watchLater"].waitForExistence(timeout: 5))
        shot(app, "11-playlists")
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["SHOTS_DIR"] {   // Survives a lost result bundle.
            try? app.screenshot().pngRepresentation.write(to: URL(filePath: folder).appending(path: "\(name).png"))
        }
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }
}
