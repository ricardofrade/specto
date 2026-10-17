import XCTest

/// A multi-language video: Playback Settings → Audio Track lists the original and its dubs,
/// and picking a dub reloads at the same position. Ends back on the original (the choice is
/// remembered across launches).
final class AudioTrackUITests: XCTestCase {
    @MainActor
    func testPickADubAndGoBack() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)"]
        app.launch()
        // MrBeast's "Eat Everything In A Grocery Store": English original plus a dozen dubs.
        app.open(try XCTUnwrap(URL(string: "dev.placeholder.specto://watch?v=plN7JMbadRg")))
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45), "Never played")
        sleep(3)
        let before = try seconds(surface)

        choose(app, "Spanish")
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 30), "Not playing after picking a dub")
        XCTAssertGreaterThanOrEqual(try seconds(surface), before, "Restarted instead of continuing")
        app.buttons["watch.settings"].tap()
        app.buttons["Audio Track"].tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "audio-tracks"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(app.buttons["Spanish"].isSelected, "Spanish isn't the selected track")
        app.buttons["English (original)"].tap()
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 30))
    }

    @MainActor
    private func choose(_ app: XCUIApplication, _ track: String) {
        app.buttons["watch.settings"].tap()
        XCTAssertTrue(app.buttons["Audio Track"].waitForExistence(timeout: 5), "No Audio Track menu")
        app.buttons["Audio Track"].tap()
        XCTAssertTrue(app.buttons[track].waitForExistence(timeout: 5), "No \(track) track")
        app.buttons[track].tap()
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }

    @MainActor
    private func seconds(_ element: XCUIElement) throws -> Int {
        try XCTUnwrap(Int((element.value as? String)?.split(separator: " ").last ?? ""))
    }
}
