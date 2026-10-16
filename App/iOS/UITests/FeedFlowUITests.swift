import XCTest

/// M1 end to end against a real Piped instance: add it, see the feed fill, play a video.
/// Run with `TEST_RUNNER_PIPED_URL=…` (never committed); skipped otherwise.
final class FeedFlowUITests: XCTestCase {
    /// Blender's channel: steady uploads with long-lived videos.
    private let channel = "UCSMOQeBJ2RAnuFungnQOxLg"

    @MainActor
    func testAddInstanceSeeFeedAndPlay() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedSubscriptions", channel]
        app.launch()

        // Empty state leads to Settings.
        app.buttons["Add Instance"].firstMatch.tap()
        app.buttons["Add Instance"].firstMatch.tap()
        let field = app.textFields["instance.url"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(piped)
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Instance added"].waitForExistence(timeout: 20))
        app.buttons["Done"].tap()

        // The feed fills from the instance (refresh + backfill after adding it).
        app.tabBars.buttons["Subscriptions"].tap()
        let list = app.scrollViews["feed.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 45), "Feed never filled")
        add(XCTAttachment(screenshot: app.screenshot()).named("feed"))

        // Play the first video.
        list.buttons.firstMatch.tap()
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 10))
        let playing = NSPredicate(format: "value == 'playing'")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: playing, evaluatedWith: surface)], timeout: 45), .completed,
                       "Never started playing (state: \(surface.value ?? "?"))")
        sleep(2)
        add(XCTAttachment(screenshot: app.screenshot()).named("playing"))
    }
}

private extension XCTAttachment {
    func named(_ name: String) -> XCTAttachment {
        self.name = name
        lifetime = .keepAlways
        return self
    }
}
