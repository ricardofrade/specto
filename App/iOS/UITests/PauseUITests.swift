import XCTest

/// Pausing from the controls over the video: it pauses, stays paused, and plays again.
final class PauseUITests: XCTestCase {
    @MainActor
    func testPauseAndPlayFromTheControls() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)"]
        app.launch()
        app.open(try XCTUnwrap(URL(string: "dev.placeholder.specto://watch?v=aqz-KE-bpKQ")))
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45), "Never played")
        sleep(5)   // The controls have faded, as when watching.

        let pause = app.playerControl("Pause")
        XCTAssertTrue(pause.waitForExistence(timeout: 5), "No Pause button")
        pause.tap()
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'paused '", 5), "Pause didn't pause: \(surface.value ?? "")")
        sleep(4)
        XCTAssertTrue((surface.value as? String ?? "").hasPrefix("paused "), "Didn't stay paused: \(surface.value ?? "")")

        let play = app.playerControl("Play")
        XCTAssertTrue(play.waitForExistence(timeout: 5), "No Play button while paused")
        play.tap()
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 10), "Play didn't resume: \(surface.value ?? "")")

        // A single tap on the picture shows the controls; it mustn't pause or play.
        sleep(5)
        surface.tap()
        sleep(1)
        XCTAssertTrue((surface.value as? String ?? "").hasPrefix("playing "), "A tap on the video changed playback")
    }

    /// Picking a format in the player re-plans the video: VP9 plays in mpv.
    @MainActor
    func testPickingVP9SwitchesToMPV() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)"]
        app.launch()
        app.open(try XCTUnwrap(URL(string: "dev.placeholder.specto://watch?v=aqz-KE-bpKQ")))
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45), "Never played")
        app.playerControl("watch.settings").tap()
        XCTAssertTrue(app.buttons["Format"].waitForExistence(timeout: 5), "No Format menu")
        app.buttons["Format"].tap()
        XCTAssertTrue(app.buttons["VP9"].waitForExistence(timeout: 5), "No VP9 choice")
        app.buttons["VP9"].tap()
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing mpv'", 30), "VP9 didn't play in mpv: \(surface.value ?? "")")
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }
}
