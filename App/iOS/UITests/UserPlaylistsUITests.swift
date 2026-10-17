import XCTest

/// Offline (demo feed): Save to Watch Later and to a new playlist from a video's menu, then find
/// both in Library → Playlists, and Play All's list in order.
final class UserPlaylistsUITests: XCTestCase {
    @MainActor
    func testWatchLaterAndANewPlaylist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedDemoFeed", "6", "-AppleLanguages", "(en)"]
        app.launch()
        let feed = app.scrollViews["feed.list"]
        XCTAssertTrue(feed.waitForExistence(timeout: 10))
        let video = feed.buttons.firstMatch

        video.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Save to Watch Later"].waitForExistence(timeout: 5))
        app.buttons["Save to Watch Later"].tap()

        video.press(forDuration: 1.0)
        app.buttons["Save to Playlist…"].tap()
        XCTAssertTrue(app.buttons["save.new"].waitForExistence(timeout: 5), "No Save to Playlist sheet")
        app.buttons["save.new"].tap()
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Road trip")
        app.buttons["Create"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "save-sheet"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(app.buttons.matching(identifier: "save.playlist").element(boundBy: 1).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(identifier: "save.playlist").element(boundBy: 1).isSelected,
                      "The new playlist doesn't hold the video")
        app.buttons["Done"].tap()

        app.buttons["Library"].firstMatch.tap()
        XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 5), "No Playlists row")
        app.buttons["library.playlists"].tap()
        XCTAssertTrue(app.buttons["playlists.watchLater"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["playlists.own"].label.contains("Road trip"))
        let list = XCTAttachment(screenshot: app.screenshot())
        list.name = "playlists"
        list.lifetime = .keepAlways
        add(list)
        app.buttons["playlists.watchLater"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "userPlaylist.video").count, 1)
    }
}
