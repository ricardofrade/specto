import XCTest

/// Screenshots of the main screens against a real instance, for design review. Run it in light
/// and in dark appearance (`xcrun simctl ui <device> appearance dark`). Attachments are kept.
final class DesignTourUITests: XCTestCase {
    @MainActor
    func testTour() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped,
                               "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"]
        app.launch()
        let list = app.scrollViews["feed.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 45))
        sleep(3)
        shot(app, "1-home")

        list.buttons.firstMatch.tap()
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45))
        sleep(8)
        shot(app, "2-watch")
        app.swipeUp()
        sleep(1)
        shot(app, "3-watch-scrolled")

        app.buttons["watch.close"].tap()
        sleep(2)
        shot(app, "4-home-after")
        list.swipeUp()
        sleep(1)
        shot(app, "5-home-scrolled")
    }

    /// The newer screens: Explore, the player's floating controls and settings menu, the Save
    /// sheet and Library → Playlists.
    @MainActor
    func testTourOfNewerScreens() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)"]
        app.launch()
        let trending = app.descendants(matching: .any)["feed.trending"].firstMatch
        XCTAssertTrue(trending.waitForExistence(timeout: 45))
        sleep(3)
        shot(app, "6-explore")

        trending.tap()
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45))
        _ = app.playerControl("watch.settings")
        shot(app, "7-player-controls")
        app.playerControl("watch.settings").tap()
        XCTAssertTrue(app.buttons["Playback Speed"].waitForExistence(timeout: 5))
        shot(app, "8-player-settings")
        app.buttons["Playback Speed"].tap()
        sleep(1)
        shot(app, "9-player-speed")
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()   // Dismiss the menu.
        sleep(1)

        app.buttons["watch.save"].tap()
        XCTAssertTrue(app.buttons["save.new"].waitForExistence(timeout: 5))
        shot(app, "10-save-sheet")
        app.buttons.matching(identifier: "save.playlist").firstMatch.tap()   // Watch Later.
        app.buttons["Done"].tap()
        app.buttons["watch.close"].tap()
        app.buttons["Library"].firstMatch.tap()
        XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 5))
        app.buttons["library.playlists"].tap()
        XCTAssertTrue(app.buttons["playlists.watchLater"].waitForExistence(timeout: 5))
        shot(app, "11-playlists")
    }

    /// The tabs and Settings: Home with the gear, Explore, Search before typing, Library's
    /// shelves, and Settings' tiles.
    @MainActor
    func testTourOfTabsAndSettings() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)",
                               "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg,UCBJycsmduvYEL83R_U4JriQ"]
        app.launch()
        let list = app.scrollViews["feed.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 45))
        sleep(3)
        shot(app, "20-home")

        // Something in Library: a video saved to Watch Later.
        list.buttons.matching(identifier: "feed.channel").firstMatch.tap()
        app.buttons["feed.allChannels"].tap()

        app.buttons["Explore"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["explore.video"].firstMatch.waitForExistence(timeout: 45))
        sleep(2)
        shot(app, "21-explore")
        app.descendants(matching: .any)["explore.video"].firstMatch.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Save to Watch Later"].waitForExistence(timeout: 5))
        app.buttons["Save to Watch Later"].tap()

        app.buttons["Library"].firstMatch.tap()
        XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 10))
        sleep(2)
        shot(app, "22-library")

        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
        sleep(1)
        shot(app, "23-settings")
        app.buttons["settings.feed"].tap()
        sleep(1)
        shot(app, "24-settings-feed")
        app.closeSettings()

        app.buttons["Search"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["search.idle"].waitForExistence(timeout: 10), "No starting screen")
        sleep(2)
        shot(app, "25-search")
    }

    /// First launch, Explore's categories (Invidious) and SponsorBlock's colours.
    @MainActor
    func testTourOfWelcomeCategoriesAndSponsorBlock() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome.addInstance"].waitForExistence(timeout: 10), "No welcome screen")
        sleep(1)
        shot(app, "40-welcome")
        app.buttons["welcome.addInstance"].tap()
        XCTAssertTrue(app.textFields["instance.url"].waitForExistence(timeout: 5), "Add Instance didn't open")
        shot(app, "41-add-instance")
        app.terminate()

        guard let invidious = ProcessInfo.processInfo.environment["INVIDIOUS_URL"] else {
            throw XCTSkip("Set INVIDIOUS_URL for Explore's categories")
        }
        app.launchArguments = ["-UITestFreshStart", "-SeedInvidious", invidious, "-AppleLanguages", "(en)",
                               "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"]
        app.launch()
        app.buttons["Explore"].firstMatch.tap()
        let chips = app.buttons.matching(identifier: "explore.category")
        XCTAssertTrue(chips.element(boundBy: 1).waitForExistence(timeout: 20), "No category chips with Invidious")
        chips.element(boundBy: 1).tap()   // Gaming.
        XCTAssertTrue(app.descendants(matching: .any)["explore.video"].firstMatch.waitForExistence(timeout: 45))
        sleep(2)
        shot(app, "42-explore-gaming")

        app.buttons["Settings"].firstMatch.tap()
        let sponsorBlock = app.buttons["settings.sponsorBlock"]
        XCTAssertTrue(sponsorBlock.waitForExistence(timeout: 5))
        sponsorBlock.tap()
        XCTAssertTrue(app.buttons["sponsorBlock.intro"].waitForExistence(timeout: 5))
        shot(app, "43-sponsorblock")
    }

    /// A channel page: header, videos, and its other tabs.
    @MainActor
    func testTourOfChannel() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)",
                               "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"]
        app.launch()
        app.buttons["Library"].firstMatch.tap()
        let channel = app.buttons["library.channelItem"].firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 10))
        channel.tap()
        XCTAssertTrue(app.buttons["channel.subscribe"].waitForExistence(timeout: 30), "No channel page")
        sleep(3)
        shot(app, "30-channel")
        app.swipeUp()
        sleep(1)
        shot(app, "31-channel-scrolled")
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["SHOTS_DIR"] {   // Survives a lost result bundle.
            try? app.screenshot().pngRepresentation.write(to: URL(filePath: folder).appending(path: "\(name).png"))
        }
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }
}
