import XCTest

/// M0 spike 7: mpv → AVPlayer handoff into Picture-in-Picture and back, with timings.
/// Needs `TEST_RUNNER_PIPED_URL`; skipped otherwise.
final class PiPSpikeUITests: XCTestCase {
    @MainActor
    func testHandoffIntoPictureInPictureAndBack() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-Harness", "pip", "-DebugPipedURL", piped, "-DebugVideoID", "aqz-KE-bpKQ"]
        app.launch()

        let status = app.staticTexts["pip.status"]
        XCTAssertTrue(wait(status, "label == 'mpv playing'", 45), "mpv never played: \(status.label)")
        sleep(3)
        app.buttons["Start PiP"].tap()
        XCTAssertTrue(wait(status, "label BEGINSWITH 'pip active'", 30), "PiP never started: \(status.label)")
        print("PiP handoff: \(status.label)")
        let pip = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        pip.name = "pip-active"
        pip.lifetime = .keepAlways
        add(pip)

        sleep(3)
        app.buttons["Stop PiP"].tap()
        XCTAssertTrue(wait(status, "label BEGINSWITH 'returned to mpv'", 15), "Never returned: \(status.label)")
        print("PiP return: \(status.label)")
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)], timeout: timeout) == .completed
    }
}
