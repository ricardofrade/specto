import XCTest

/// The player's controls against a real instance: the scrubber seeks, double-tapping the right
/// side jumps forward, and a phone turned sideways plays full screen.
final class PlayerControlsUITests: XCTestCase {
    @MainActor
    func testScrubDoubleTapAndLandscape() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped,
                               "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"]
        app.launch()
        let list = app.scrollViews["feed.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 45))
        list.buttons.firstMatch.tap()
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45))
        sleep(2)

        // Scrubber: drag to about 60 % of a 2:29 video (~89 s).
        let scrubber = app.otherElements["watch.scrubber"]
        if !scrubber.exists { surface.tap() }
        // The first tap can land during the zoom into the player; tap once more if needed.
        if !scrubber.waitForExistence(timeout: 3) { surface.tap() }
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5), "No scrubber")
        shot(app, "controls")
        let start = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3))
        let end = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.3))
        start.press(forDuration: 0.1, thenDragTo: end)
        sleep(3)
        let scrubbed = try seconds(surface)
        XCTAssertTrue((75...110).contains(scrubbed), "Scrubbing landed at \(scrubbed) s")

        // Double-tap the right side: +10 s.
        let before = try seconds(surface)
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.4)).doubleTap()
        sleep(3)
        let after = try seconds(surface)
        XCTAssertGreaterThanOrEqual(after, before + 10, "Double-tap didn't jump forward (\(before) → \(after))")

        // Sideways: full screen, still playing.
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        shot(app, "landscape")
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 10))
        XCTAssertGreaterThan(surface.frame.height, app.windows.firstMatch.frame.height * 0.9, "Not full screen")
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }

    @MainActor
    private func seconds(_ element: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(element.value as? String)
        return try XCTUnwrap(Int(value.split(separator: " ").last ?? ""))
    }
}
