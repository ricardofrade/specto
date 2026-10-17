import XCTest

/// The TV app against a real Piped instance, driven with the Siri Remote: the billboard's Play →
/// skip forward → Down for Chapters and Up Next → Menu twice back to Home, where the video now
/// shows under Continue Watching.
final class TVBrowseAndPlayUITests: XCTestCase {
    @MainActor
    func testHomeToPlayerAndBack() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped,
                               "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"]
        app.launch()
        let remote = XCUIRemote.shared

        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 60), "The billboard never loaded")
        sleep(2)
        attach(app, "home")

        // Focus starts in the tab bar; Down reaches the billboard's Play button.
        remote.press(.down)
        sleep(1)
        attach(app, "focused-card")
        XCTAssertTrue(app.buttons["Play"].hasFocus, "Down from the tab bar should land on the billboard's Play")
        remote.press(.select)

        let player = app.otherElements["tv.player"]
        XCTAssertTrue(wait(player, "value BEGINSWITH 'playing '", 60), "Never played: \(player.value ?? "none")")
        sleep(5)
        attach(app, "player")
        let before = try seconds(player)
        remote.press(.right)
        // An exact seek on a network stream finishes once the new data arrives; allow for it.
        var after = before
        for _ in 0..<20 where after < before + 9 {
            usleep(500_000)
            after = try seconds(player)
        }
        XCTAssertGreaterThanOrEqual(after, before + 9, "Right didn't skip forward (\(before) → \(after))")

        remote.press(.down)
        XCTAssertTrue(app.staticTexts["Up Next"].waitForExistence(timeout: 5), "No Up Next panel")
        sleep(1)
        attach(app, "panel")
        remote.press(.menu)     // Closes the panel…
        sleep(1)
        remote.press(.menu)     // …then the player.
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 10), "No Continue Watching shelf")
        attach(app, "home-after")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }

    @MainActor
    private func seconds(_ element: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(element.value as? String)
        return try XCTUnwrap(Int(value.split(separator: " ").last ?? ""))
    }
}
