import XCTest

/// PeerTube on its own, against a public server (Blender's): Explore, playing, search, a
/// subscribed channel on Home, and the public-server list. Needs the network; no secrets.
final class PeerTubeUITests: XCTestCase {
    private let server = "https://video.blender.org"
    private let channel = "pt:video.blender.org:blender_open_movies@video.blender.org"

    @MainActor
    func testExplorePlaySearchAndHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedPeerTube", server, "-SeedSubscriptions", channel,
                               "-AppleLanguages", "(en)"]
        app.launch()

        // Home: the subscribed PeerTube channel's videos.
        XCTAssertTrue(app.scrollViews["feed.list"].waitForExistence(timeout: 45), "No PeerTube videos on Home")
        sleep(2)
        shot(app, "70-peertube-home")

        app.buttons["Explore"].firstMatch.tap()
        let video = app.descendants(matching: .any)["explore.video"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 45), "No PeerTube trending")
        XCTAssertTrue(app.staticTexts["Trending on PeerTube"].exists)
        sleep(2)
        shot(app, "71-peertube-explore")

        video.tap()
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45), "A PeerTube video didn't play: \(surface.value ?? "")")
        sleep(4)
        shot(app, "72-peertube-watch")
        app.buttons["watch.close"].tap()

        app.buttons["Search"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("blender\n")
        XCTAssertTrue(app.collectionViews["search.results"].waitForExistence(timeout: 30), "No PeerTube search results")
        shot(app, "73-peertube-search")
    }

    @MainActor
    func testPublicServersToChooseFrom() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["welcome.addInstance"].tap()
        let server = app.buttons.matching(identifier: "instance.publicServer").firstMatch
        XCTAssertTrue(server.waitForExistence(timeout: 30), "No public PeerTube servers")
        shot(app, "74-public-servers")

        // Search the index as you type.
        let search = app.textFields["publicServers.search"]
        search.tap()
        search.typeText("blender")
        let blender = app.buttons.matching(NSPredicate(format: "identifier == 'instance.publicServer' AND label CONTAINS[c] 'blender'"))
        XCTAssertTrue(blender.firstMatch.waitForExistence(timeout: 20), "Searching the index found nothing")
        shot(app, "75-public-servers-search")
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
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
