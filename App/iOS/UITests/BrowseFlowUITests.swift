import XCTest

/// M2 flows against a real Piped instance (`TEST_RUNNER_PIPED_URL`, never committed):
/// search, watch → channel, dismiss into the mini-player and reopen.
final class BrowseFlowUITests: XCTestCase {
    private let channel = "UCSMOQeBJ2RAnuFungnQOxLg"

    @MainActor
    private func launchWithInstance() throws -> XCUIApplication {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedSubscriptions", channel]
        app.launch()
        app.buttons["Add Instance"].firstMatch.tap()      // Feed's empty state → Instances screen.
        XCTAssertTrue(app.navigationBars["Instances"].waitForExistence(timeout: 5))
        app.buttons["Add Instance"].firstMatch.tap()
        let field = app.textFields["instance.url"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(piped)
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Instance added"].waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
        return app
    }

    @MainActor
    func testSearchFindsVideos() throws {
        let app = try launchWithInstance()
        app.buttons["Search"].firstMatch.tap()   // Tab bar on iPhone, top bar or sidebar on iPad.
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("big buck bunny\n")
        XCTAssertTrue(app.collectionViews["search.results"].waitForExistence(timeout: 30))
        XCTAssertGreaterThan(app.collectionViews["search.results"].cells.count, 3)
        attach(app, "search")
    }

    @MainActor
    func testWatchChannelMiniPlayerAndReopen() throws {
        let app = try launchWithInstance()
        app.buttons["Subscriptions"].firstMatch.tap()   // Tab bar on iPhone, top bar or sidebar on iPad.
        let list = app.scrollViews["feed.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 45))
        list.buttons.firstMatch.tap()

        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(waitFor(surface, "value BEGINSWITH 'playing '", 45), "Never played")

        // Channel opens inside the Watch sheet.
        app.buttons["watch.channel"].tap()
        XCTAssertTrue(app.buttons["channel.subscribe"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["channel.subscribe"].label, "Subscribed")
        attach(app, "channel")
        app.navigationBars.buttons.firstMatch.tap()

        // Swipe the sheet away: playback continues in the mini-player.
        app.swipeDown(velocity: .fast)
        let mini = app.otherElements["miniplayer"]
        XCTAssertTrue(mini.waitForExistence(timeout: 10), "No mini-player after dismissing")
        attach(app, "miniplayer")

        mini.tap()
        XCTAssertTrue(waitFor(surface, "value BEGINSWITH 'playing '", 15), "Reopened player isn't playing")
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
