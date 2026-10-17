import XCTest

/// Offline (the demo feed, one channel): mark a video as watched, hide its channel from Home,
/// and bring it back from Library → Channels.
final class FeedHousekeepingUITests: XCTestCase {
    @MainActor
    func testMarkWatchedHideAndShowChannel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedDemoFeed", "12"]
        app.launch()
        let feed = app.scrollViews["feed.list"]
        XCTAssertTrue(feed.waitForExistence(timeout: 10))
        // The newest video leads Home; once watched, the next unwatched one takes its place, so
        // follow the video by its title rather than its position.
        let video = feed.buttons.matching(NSPredicate(format: "label CONTAINS 'Demo video 1 with'")).firstMatch
        let first = feed.buttons.firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 5))

        video.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Mark as Watched"].waitForExistence(timeout: 5), "No Mark as Watched")
        shot(app, "menu")
        app.buttons["Mark as Watched"].tap()
        sleep(1)
        if !video.isHittable { feed.swipeUp() }
        video.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Mark as Unwatched"].waitForExistence(timeout: 5), "Not marked as watched")

        let hide = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hide ' AND label ENDSWITH ' from Home'")).firstMatch
        XCTAssertTrue(hide.exists, "No Hide from Home")
        hide.tap()
        XCTAssertTrue(waitForGone(first), "Hidden channel still on Home")

        app.buttons["Library"].firstMatch.tap()
        app.buttons["library.channels"].tap()
        let row = app.buttons["channels.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hidden from Home"].exists, "Not marked hidden in Channels")
        shot(app, "channels-hidden")
        row.swipeRight()
        app.buttons["Show on Home"].tap()

        app.buttons["Home"].firstMatch.tap()
        XCTAssertTrue(feed.buttons.firstMatch.waitForExistence(timeout: 10), "Channel didn't come back to Home")
    }

    @MainActor
    private func waitForGone(_ element: XCUIElement) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)],
                         timeout: 10) == .completed
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
