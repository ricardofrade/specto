import XCTest

/// M0 spike 5: the player sheet can be dismissed and reopened while playback continues.
/// Needs real stream URLs (never committed): run with
/// `TEST_RUNNER_DEBUG_VIDEO_URL=… TEST_RUNNER_DEBUG_AUDIO_URL=… xcodebuild test …`.
final class PlaybackSpikeUITests: XCTestCase {
    @MainActor
    func testDismissAndReopenKeepsPlaying() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let video = environment["DEBUG_VIDEO_URL"], let audio = environment["DEBUG_AUDIO_URL"] else {
            throw XCTSkip("Set DEBUG_VIDEO_URL and DEBUG_AUDIO_URL to run against real streams")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-Harness", "player", "-DebugVideoURL", video, "-DebugAudioURL", audio, "-DebugAutoplay"]
        app.launch()

        let surface = app.otherElements["debug.surface"]
        XCTAssertTrue(surface.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForState("playing", in: app, timeout: 30), "Never reached playing")
        add(screenshot(app, "playing"))

        // Dismiss the sheet; playback must carry on without a surface.
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(surface.waitForNonExistence(timeout: 5))
        let positionBefore = try position(in: app)
        sleep(3)
        let positionAfter = try position(in: app)
        XCTAssertGreaterThan(positionAfter, positionBefore, "Playback stopped when the player was dismissed")
        XCTAssertTrue(waitForState("playing", in: app, timeout: 3), "Status: \(status(app).label)")

        // Reopen: the same session attaches the new surface without reloading.
        app.buttons["Open player"].tap()
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        sleep(2)
        XCTAssertGreaterThanOrEqual(try position(in: app), positionAfter)
        XCTAssertTrue(waitForState("playing", in: app, timeout: 3), "Status: \(status(app).label)")
        add(screenshot(app, "reopened"))
    }

    /// The status line reads "<state> <m:ss>".
    @MainActor
    private func status(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["debug.status"].firstMatch
    }

    @MainActor
    private func waitForState(_ state: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let matches = NSPredicate(format: "label BEGINSWITH %@", state + " ")
        return XCTWaiter().wait(for: [expectation(for: matches, evaluatedWith: status(app))], timeout: timeout) == .completed
    }

    @MainActor
    private func position(in app: XCUIApplication) throws -> Int {
        XCTAssertTrue(status(app).waitForExistence(timeout: 5))
        let time = try XCTUnwrap(status(app).label.split(separator: " ").last)
        let parts = time.split(separator: ":").compactMap { Int($0) }
        return try XCTUnwrap(parts.count == 2 ? parts[0] * 60 + parts[1] : nil)
    }

    @MainActor
    private func screenshot(_ app: XCUIApplication, _ name: String) -> XCTAttachment {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
