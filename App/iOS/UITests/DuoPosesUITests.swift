import XCTest

/// iPhone Duo poses: opens a video, then screenshots every few seconds while someone changes the
/// pose in Xcode's Device Hub (open, closed, tabletop, book). Playback must never stop.
/// Runs only with `DUO_POSES=1`.
final class DuoPosesUITests: XCTestCase {
    @MainActor
    func testPosesWhilePlaying() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DUO_POSES"] == "1", let piped = environment["PIPED_URL"] else {
            throw XCTSkip("Set DUO_POSES=1 and PIPED_URL, and change poses in Device Hub while it runs")
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

        // A stall is a sample that isn't playing while the position stopped moving before the end;
        // "paused" at the video's last second is the video finishing, not a stall.
        var stalls: [String] = []
        var lastSeconds = -1
        for index in 0..<19 {
            sleep(8)
            let value = surface.value as? String ?? "missing"
            let seconds = Int(value.split(separator: " ").last ?? "") ?? -1
            let finished = value.hasPrefix("ended ") || (value.hasPrefix("paused ") && seconds == lastSeconds)
            if !value.hasPrefix("playing "), !finished { stalls.append("\(index): \(value)") }
            lastSeconds = seconds
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = String(format: "pose-%02d", index)
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCTAssertTrue(stalls.isEmpty, "Playback stopped: \(stalls)")
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }
}
