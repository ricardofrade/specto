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
}
