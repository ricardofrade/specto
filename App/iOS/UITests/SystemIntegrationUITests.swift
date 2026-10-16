import XCTest

/// M4 against a real Piped instance: audio mode keeps the position, Cast lists receivers.
final class SystemIntegrationUITests: XCTestCase {
    @MainActor
    func testAudioModeAndCastMenu() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"]
        app.launch()
        app.buttons["Add Instance"].firstMatch.tap()      // Feed's empty state → Instances screen.
        XCTAssertTrue(app.navigationBars["Instances"].waitForExistence(timeout: 5))
        app.buttons["Add Instance"].firstMatch.tap()
        let field = app.textFields["instance.url"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(piped)
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Instance added"].waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
        app.buttons["Subscriptions"].firstMatch.tap()
        let list = app.scrollViews["feed.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 45))
        list.buttons.firstMatch.tap()

        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45))
        sleep(4)
        let before = try seconds(surface)

        // Audio only: AVPlayer takes over at the same position.
        app.buttons["watch.audioMode"].tap()
        XCTAssertTrue(app.buttons["Video"].waitForExistence(timeout: 10), "Mode didn't switch")
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 20), "Audio mode isn't playing")
        sleep(2)
        let after = try seconds(surface)
        XCTAssertGreaterThanOrEqual(after, before, "Position went backwards across the switch")
        XCTAssertLessThan(after, before + 10, "Position jumped across the switch")

        // Back to video.
        app.buttons["watch.audioMode"].tap()
        XCTAssertTrue(app.buttons["Audio only"].waitForExistence(timeout: 10))
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 20))

        // Cast: the menu lists receivers on the network (nothing is selected).
        let cast = app.buttons["watch.cast"]
        if cast.waitForExistence(timeout: 10) {
            cast.tap()
            let receivers = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'chromecast' OR label CONTAINS[c] 'bravia'"))
            XCTAssertTrue(receivers.firstMatch.waitForExistence(timeout: 5), "No receivers listed")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "cast-menu"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.tap()   // Dismiss the menu without casting.
        } else {
            print("No Cast receivers discovered from the simulator")
        }
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }

    @MainActor
    private func seconds(_ surface: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(surface.value as? String)
        return try XCTUnwrap(Int(value.split(separator: " ").last ?? ""))
    }
}
