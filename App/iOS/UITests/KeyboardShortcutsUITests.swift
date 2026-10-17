import XCTest

/// iPad hardware keyboard: space pauses and resumes the player, → jumps forward; space in the
/// Search field still types.
final class KeyboardShortcutsUITests: XCTestCase {
    @MainActor
    func testSpaceAndArrowsControlThePlayer() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Hardware keyboard shortcuts: iPad") }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped,
                               "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"]
        app.launch()

        app.buttons["Home"].firstMatch.tap()
        let list = app.scrollViews["feed.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 45))
        list.buttons.firstMatch.tap()
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45))
        sleep(2)

        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'paused '", 5), "Space didn't pause")
        let before = try seconds(surface)
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        sleep(1)
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 10), "Space didn't resume")
        sleep(2)    // Paused players don't report position; read it once playing again.
        XCTAssertGreaterThanOrEqual(try seconds(surface), before + 9, "→ didn't jump forward")

        // With the player closed (still playing in the mini-player), a space in Search types.
        app.buttons["watch.close"].tap()
        
        app.buttons["Search"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        // Narrower iPads collapse the field into a Search button in the navigation bar.
        if !field.waitForExistence(timeout: 5) { app.navigationBars["Search"].buttons["Search"].tap() }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("big buck")
        XCTAssertEqual(field.value as? String, "big buck")

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
