import XCTest

/// The player's Playback Settings menu. Quality (ADR 0007): picking one reloads that height at the
/// same position, and Auto goes back to the planner's choice. Sleep Timer: a countdown shows.
final class PlaybackSettingsUITests: XCTestCase {
    @MainActor
    func testPickAQualityAndGoBackToAuto() throws {
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
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45))
        let auto = try XCTUnwrap(surface.value as? String)
        sleep(4)
        let before = try seconds(surface)

        choose(app, "360p")
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing ' AND value CONTAINS ' 360p '", 30),
                      "Not playing 360p: \(surface.value ?? "")")
        XCTAssertGreaterThanOrEqual(try seconds(surface), before, "Restarted instead of continuing")

        app.playerControl("watch.settings").tap()
        app.buttons["Quality"].tap()
        shot(app, "quality-menu")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Auto'")).firstMatch.tap()
        let height = auto.split(separator: " ")[2]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing ' AND value CONTAINS ' \(height) '", 30),
                      "Auto didn't go back to \(height): \(surface.value ?? "")")
    }

    @MainActor
    func testSleepTimerCountsDown() throws {
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

        app.playerControl("watch.settings").tap()
        XCTAssertTrue(app.buttons["Sleep Timer"].waitForExistence(timeout: 5), "No Sleep Timer menu")
        app.buttons["Sleep Timer"].tap()
        let fifteen = app.buttons.matching(NSPredicate(format: "label CONTAINS '15'")).firstMatch
        XCTAssertTrue(fifteen.waitForExistence(timeout: 5), "No 15-minute option")
        fifteen.tap()

        app.playerControl("watch.settings").tap()
        // The menu row's label carries the countdown ("Sleep Timer, 15 min left").
        let countdown = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'min left'")).firstMatch
        shot(app, "sleep-timer")
        XCTAssertTrue(countdown.waitForExistence(timeout: 5), "No countdown in the menu")
    }

    @MainActor
    private func choose(_ app: XCUIApplication, _ quality: String) {
        app.playerControl("watch.settings").tap()
        XCTAssertTrue(app.buttons["Quality"].waitForExistence(timeout: 5), "No Quality menu")
        app.buttons["Quality"].tap()
        XCTAssertTrue(app.buttons[quality].waitForExistence(timeout: 5), "No \(quality) option")
        app.buttons[quality].tap()
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

    @MainActor
    private func seconds(_ element: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(element.value as? String)
        return try XCTUnwrap(Int(value.split(separator: " ").last ?? ""))
    }
}
