import XCTest

/// Library against a real instance: a watched video shows in Continue Watching and History, and
/// swiping it out of History removes it.
final class LibraryUITests: XCTestCase {
    @MainActor
    func testWatchedVideoAppearsAndCanBeRemoved() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped,
                               "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"]
        app.launch()
        app.buttons["Library"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Nothing here yet"].waitForExistence(timeout: 10))

        app.buttons["Home"].firstMatch.tap()
        let feed = app.scrollViews["feed.list"]
        XCTAssertTrue(feed.waitForExistence(timeout: 45))
        feed.buttons.firstMatch.tap()
        XCTAssertTrue(wait(app.otherElements["watch.surface"], "value BEGINSWITH 'playing '", 45))
        sleep(8)    // Past the 5 s a video needs to count as started.
        app.buttons["watch.close"].tap()

        app.buttons["Library"].firstMatch.tap()
        let list = app.collectionViews["library.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10), "No library list")
        XCTAssertTrue(app.staticTexts["Continue Watching"].exists)
        XCTAssertTrue(app.staticTexts["History"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "library"
        shot.lifetime = .keepAlways
        add(shot)

        let historyRow = app.buttons["library.history"].firstMatch
        XCTAssertTrue(historyRow.exists, "No history row")
        historyRow.swipeLeft()
        let remove = app.buttons["Remove"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "No Remove action")
        remove.tap()
        XCTAssertTrue(wait(app.staticTexts["History"], "exists == false", 10), "History row wasn't removed")
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }
}
