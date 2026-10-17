import XCTest

/// Home before any subscriptions: what's trending, and from a video its channel, to subscribe.
final class ExploreUITests: XCTestCase {
    @MainActor
    func testTrendingLeadsToAChannelToSubscribe() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)"]
        app.launch()
        let video = app.descendants(matching: .any)["feed.trending"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 45), "No trending videos on an empty Home")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "explore"
        attachment.lifetime = .keepAlways
        add(attachment)

        video.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Go to Channel"].waitForExistence(timeout: 5))
        app.buttons["Go to Channel"].tap()
        XCTAssertTrue(app.buttons["channel.subscribe"].waitForExistence(timeout: 30), "No channel page")
        XCTAssertEqual(app.buttons["channel.subscribe"].label, "Subscribe")
    }

    /// The Explore tab: trending, number one large, cached for next time; the gear opens Settings.
    @MainActor
    func testExploreTabShowsTrending() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)",
                               "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"]
        app.launch()
        app.buttons["Explore"].firstMatch.tap()
        let video = app.descendants(matching: .any)["explore.video"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 45), "No trending videos in Explore")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Trending'")).firstMatch.exists)
        sleep(2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "explore-tab"
        shot.lifetime = .keepAlways
        add(shot)
        if let folder = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? app.screenshot().pngRepresentation.write(to: URL(filePath: folder).appending(path: "explore-tab.png"))
        }

        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5), "Gear didn't open Settings")
        app.closeSettings()
        XCTAssertTrue(video.waitForExistence(timeout: 5))
    }
}
