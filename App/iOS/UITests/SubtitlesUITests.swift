import XCTest

/// Subtitles against a real instance: pick a track from the player's menu, see lines appear,
/// turn them off from the captions button.
final class SubtitlesUITests: XCTestCase {
    @MainActor
    func testPickTrackAndSeeSubtitles() throws {
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
        XCTAssertTrue(wait(app.otherElements["watch.surface"], "value BEGINSWITH 'playing '", 45))

        // Settings over the video → Subtitles.
        sleep(3)   // The tracks arrive with the details.
        app.playerControl("watch.settings").tap()
        let menu = app.buttons["Subtitles"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "No Subtitles in Settings")
        menu.tap()
        let english = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'English'")).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 5), "No English track listed")
        sleep(1)
        english.tap()

        let subtitle = app.staticTexts["subtitle"]
        XCTAssertTrue(subtitle.waitForExistence(timeout: 20), "No subtitle line appeared")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "subtitles"
        shot.lifetime = .keepAlways
        add(shot)
        print("SUBTITLE: \(subtitle.label)")
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }
}
