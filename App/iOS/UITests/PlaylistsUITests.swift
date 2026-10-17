import XCTest

/// Playlists against a real instance: a channel's Playlists tab, a playlist's Play All, saving it,
/// and finding it again in Library → Playlists.
final class PlaylistsUITests: XCTestCase {
    @MainActor
    func testOpenSavePlayAllAndFindInLibrary() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped,
                               "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"]
        app.launch()

        // Library → Channels → Blender → Playlists.
        app.buttons["Library"].firstMatch.tap()
        let channels = app.buttons["library.channels"]
        XCTAssertTrue(channels.waitForExistence(timeout: 10))
        channels.tap()
        let row = app.buttons["channels.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let tabs = app.segmentedControls["channel.tab"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 30), "No Videos/Playlists picker")
        tabs.buttons["Playlists"].tap()
        let playlist = app.buttons["channel.playlist"].firstMatch
        XCTAssertTrue(playlist.waitForExistence(timeout: 30), "No playlists on the channel")
        shot(app, "channel-playlists")
        playlist.tap()

        let video = app.buttons["playlist.video"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 30), "Playlist didn't load")
        app.buttons["playlist.save"].tap()
        XCTAssertTrue(app.buttons["playlist.save"].label.contains("Saved"))
        shot(app, "playlist")

        app.buttons["playlist.playAll"].tap()
        let surface = app.otherElements["watch.surface"]
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "value BEGINSWITH 'playing '"),
                                                          evaluatedWith: surface)], timeout: 45), .completed)
        app.buttons["watch.close"].tap()

        // Back to the Library root: the saved playlist is there.
        app.buttons["Library"].firstMatch.tap()
        app.buttons["Library"].firstMatch.tap()
        let playlists = app.buttons["library.playlists"]
        XCTAssertTrue(playlists.waitForExistence(timeout: 10), "No Playlists row")
        playlists.tap()
        XCTAssertTrue(app.buttons["playlists.row"].firstMatch.waitForExistence(timeout: 5), "Saved playlist missing")
        shot(app, "saved-playlists")
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
