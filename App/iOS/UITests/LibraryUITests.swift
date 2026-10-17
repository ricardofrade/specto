import XCTest

/// Library against a real instance: a watched video shows in Continue Watching and History, and
/// swiping it out of History removes it.
final class LibraryUITests: XCTestCase {
    /// Offline (the demo feed's one channel): Library → Channels, search, swipe to unsubscribe.
    @MainActor
    func testChannelsSearchAndUnsubscribe() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedDemoFeed", "5"]
        app.launch()
        app.buttons["Library"].firstMatch.tap()
        let channelsRow = app.buttons["library.channels"]
        XCTAssertTrue(channelsRow.waitForExistence(timeout: 10), "No Channels row")
        channelsRow.tap()
        let row = app.buttons["channels.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No channel rows")
        XCTAssertEqual(row.label, "Demo")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "channels"
        shot.lifetime = .keepAlways
        add(shot)

        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5), "No search field")
        search.tap()
        search.typeText("zzz")
        XCTAssertTrue(app.staticTexts["No Results for “zzz”"].waitForExistence(timeout: 5)
                      || !app.buttons["channels.row"].exists, "Search didn't filter")
        search.buttons.firstMatch.tap()   // Clear: every channel again.

        XCTAssertTrue(row.waitForExistence(timeout: 5))
        // Notifications off for this channel, from its menu; the row says so.
        row.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Turn Off Notifications"].waitForExistence(timeout: 5))
        app.buttons["Turn Off Notifications"].tap()
        XCTAssertTrue(wait(row, "label CONTAINS 'Notifications off'", 5), "Row doesn't say notifications are off: \(row.label)")
        row.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Turn On Notifications"].waitForExistence(timeout: 5))
        app.buttons["Turn On Notifications"].tap()
        XCTAssertTrue(wait(row, "NOT (label CONTAINS 'Notifications off')", 5))

        row.swipeLeft()
        let unsubscribe = app.buttons["Unsubscribe"].firstMatch
        XCTAssertTrue(unsubscribe.waitForExistence(timeout: 5), "No Unsubscribe action")
        unsubscribe.tap()
        XCTAssertTrue(app.staticTexts["No channels"].waitForExistence(timeout: 5), "Still subscribed")
    }

    /// Offline: the search field finds watched videos by title words, and only those.
    @MainActor
    func testHistorySearch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedDemoFeed", "6", "-SeedHistory", "4", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["Library"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["library.history"].firstMatch.waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        if !search.exists { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5), "No search field")
        search.tap()
        search.typeText("VIDEO 4")
        let result = app.descendants(matching: .any).matching(identifier: "library.historyResult")
        XCTAssertTrue(result.firstMatch.waitForExistence(timeout: 5), "No results")
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.firstMatch.label.contains("Demo video 4"), result.firstMatch.label)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "history-search"
        shot.lifetime = .keepAlways
        add(shot)

        search.typeText(" zzz")
        XCTAssertTrue(app.staticTexts["No Results for “VIDEO 4 zzz”"].waitForExistence(timeout: 5), "Didn't show no results")
        search.buttons.firstMatch.tap()   // Clear: the Library again.
        XCTAssertTrue(app.descendants(matching: .any)["library.history"].firstMatch.waitForExistence(timeout: 5))
    }

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
        // Only the subscription so far: the Channels row, nothing watched.
        XCTAssertTrue(app.buttons["library.channels"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Continue Watching"].exists)

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
