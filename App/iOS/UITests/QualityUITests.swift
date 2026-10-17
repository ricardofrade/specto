import XCTest

/// ADR 0007: picking a quality in the player reloads that height at the same position, and
/// Auto goes back to the planner's choice.
final class QualityUITests: XCTestCase {
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

        app.buttons["watch.settings"].tap()
        app.buttons["Quality"].tap()
        shot(app, "quality-menu")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Auto'")).firstMatch.tap()
        let height = auto.split(separator: " ")[2]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing ' AND value CONTAINS ' \(height) '", 30),
                      "Auto didn't go back to \(height): \(surface.value ?? "")")
    }

    @MainActor
    private func choose(_ app: XCUIApplication, _ quality: String) {
        app.buttons["watch.settings"].tap()
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
