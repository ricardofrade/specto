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
}
