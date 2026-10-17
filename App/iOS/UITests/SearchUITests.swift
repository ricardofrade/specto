import XCTest

/// Search against a real instance: suggestions while typing, the Channels and Playlists filters,
/// and the search kept in Recent.
final class SearchUITests: XCTestCase {
    @MainActor
    func testFiltersSuggestionsAndRecent() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped]
        app.launch()
        app.buttons["Search"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("blender")
        let suggestion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'blender '")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 15), "No suggestions")
        shot(app, "suggestions")
        field.typeText("\n")

        let results = app.collectionViews["search.results"]
        XCTAssertTrue(results.waitForExistence(timeout: 30), "No video results")

        app.buttons["Channels"].firstMatch.tap()
        let channel = app.buttons["search.channel"].firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 30), "No channel results")
        shot(app, "channels")
        app.buttons["Playlists"].firstMatch.tap()
        XCTAssertTrue(app.buttons["search.playlist"].firstMatch.waitForExistence(timeout: 30), "No playlist results")
        shot(app, "playlists")

        // Clearing the field shows the search under Recent.
        field.buttons.firstMatch.tap()
        let recent = app.buttons["search.recent"].firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 5), "Search not kept in Recent")
        XCTAssertEqual(recent.label, "blender")
        shot(app, "recent")
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
