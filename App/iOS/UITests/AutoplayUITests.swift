import XCTest

/// Autoplay: at the end of a video with nothing queued, a card counts down to the first
/// suggestion, which then plays by itself.
final class AutoplayUITests: XCTestCase {
    @MainActor
    func testCountdownThenTheNextVideoPlays() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)",
                               "-playback.autoplay", "YES"]
        app.launch()
        app.open(try XCTUnwrap(URL(string: "dev.placeholder.specto://watch?v=aqz-KE-bpKQ")))
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45), "Never played")
        sleep(3)   // Details (and so the suggestions) arrive.

        // Scrub to the end.
        let scrubber = app.otherElements["watch.scrubber"]
        if !scrubber.exists { surface.tap() }
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5), "No scrubber")
        scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.999, dy: 0.3)))

        let card = app.descendants(matching: .any)["watch.upNext"]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "No Up Next card at the end")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "up-next"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(wait(card, "exists == false", 15), "The countdown never finished")
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45), "The next video didn't play")
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }
}
