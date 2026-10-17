import XCTest

/// The channel strip above Home: tap a channel to see only its videos, All to see everyone's.
final class ChannelStripUITests: XCTestCase {
    @MainActor
    func testTappingAChannelFiltersHome() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)",
                               "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg,UCBJycsmduvYEL83R_U4JriQ"]
        app.launch()
        let channels = app.buttons.matching(identifier: "feed.channel")
        XCTAssertTrue(channels.element(boundBy: 1).waitForExistence(timeout: 45), "No channel strip")
        sleep(2)
        shot(app, "strip")

        let second = channels.element(boundBy: 1)
        let name = second.label
        second.tap()
        XCTAssertTrue(app.buttons["feed.allChannels"].waitForExistence(timeout: 5), "No All button while filtered")
        XCTAssertTrue(second.isSelected)
        // Every video on Home is now that channel's.
        let cells = app.scrollViews["feed.list"].buttons.matching(NSPredicate(format: "label CONTAINS %@", name))
        XCTAssertGreaterThan(cells.count, 0, "No videos from \(name)")
        sleep(1)
        shot(app, "filtered")

        app.buttons["feed.allChannels"].tap()
        XCTAssertFalse(app.buttons["feed.allChannels"].waitForExistence(timeout: 2))
        XCTAssertFalse(second.isSelected)
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? app.screenshot().pngRepresentation.write(to: URL(filePath: folder).appending(path: "\(name).png"))
        }
    }
}
