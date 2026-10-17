import XCTest

/// Shorts against a real instance: the Home shelf opens the vertical player, swiping up plays
/// the next one, and closing stops playback.
final class ShortsUITests: XCTestCase {
    @MainActor
    func testShelfPlayerAndSwipe() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        // Channels that post Shorts; "-feed.hideShorts NO" shows the shelf without touching saved settings.
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped,
                               "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg,UCBJycsmduvYEL83R_U4JriQ",
                               "-feed.hideShorts", "NO"]
        app.launch()
        let short = app.buttons["feed.short"].firstMatch
        let feed = app.scrollViews["feed.list"]
        XCTAssertTrue(feed.waitForExistence(timeout: 45))
        for _ in 0..<4 where !short.exists { feed.swipeUp() }
        XCTAssertTrue(short.waitForExistence(timeout: 30), "No Shorts shelf")
        shot(app, "shelf")
        short.tap()

        let surface = app.otherElements["shorts.surface"]
        let played = wait(surface, "value BEGINSWITH 'playing '", 45)
        shot(app, "after-tap")
        XCTAssertTrue(played, "First Short never played: \(surface.exists ? (surface.value as? String ?? "?") : "no surface")")
        let first = try XCTUnwrap((surface.value as? String)?.split(separator: " ")[1])
        shot(app, "playing")

        app.swipeUp()
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing ' AND NOT (value CONTAINS '\(first)')", 45),
                      "Swiping up didn't play the next Short")
        app.buttons["shorts.close"].tap()
        XCTAssertTrue(feed.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["miniPlayer"].exists)
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
