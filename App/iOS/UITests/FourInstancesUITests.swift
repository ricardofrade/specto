import XCTest

/// Piped, Invidious, a linked YT Zero and a PeerTube server together (ADR 0018): Instances
/// explains who does what, Search switches between YouTube and PeerTube, PeerTube's videos
/// carry their mark, and a video from each network plays.
final class FourInstancesUITests: XCTestCase {
    @MainActor
    func testAllFourKindsTogether() throws {
        let env = ProcessInfo.processInfo.environment
        guard let piped = env["PIPED_URL"], let invidious = env["INVIDIOUS_URL"],
              let ytZero = env["YTZERO_URL"], let token = env["YTZERO_TOKEN"] else {
            throw XCTSkip("Set PIPED_URL, INVIDIOUS_URL, YTZERO_URL and YTZERO_TOKEN (scripts/live-ui-tests.sh does)")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-SeedInvidious", invidious,
                               "-SeedYTZero", ytZero, token, "-SeedPeerTube", "https://video.blender.org",
                               "-AppleLanguages", "(en)"]
        app.launch()

        // Instances: one section per network, saying who keeps the subscriptions.
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["settings.instances"].firstMatch.tap()
        let rows = app.descendants(matching: .any).matching(identifier: "instance.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "No instance rows")
        XCTAssertEqual(rows.count, 4)
        let ytZeroHost = try XCTUnwrap(URL(string: ytZero)?.host())
        let owner = NSPredicate(format: "label CONTAINS %@", "kept in your account on \(ytZeroHost)")
        XCTAssertTrue(app.staticTexts.matching(owner).firstMatch.exists, "No account explanation")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Search looks on every server'"))
            .firstMatch.exists, "No PeerTube explanation")
        shot(app, "four-instances")
        app.closeSettings()

        // Search on PeerTube: Blender's own server, marked as PeerTube; one plays.
        app.buttons["Search"].firstMatch.tap()
        let network = app.segmentedControls["search.network"]
        XCTAssertTrue(network.waitForExistence(timeout: 5), "No YouTube | PeerTube switch")
        network.buttons["PeerTube"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("sprite fright\n")
        let results = app.collectionViews["search.results"]
        XCTAssertTrue(results.waitForExistence(timeout: 30), "No PeerTube results")
        let marked = results.buttons.matching(NSPredicate(format: "label CONTAINS 'From PeerTube'"))
        if !marked.firstMatch.waitForExistence(timeout: 10) { print("RESULTS\n\(results.debugDescription)") }
        XCTAssertTrue(marked.firstMatch.waitForExistence(timeout: 10), "PeerTube results aren't marked")
        shot(app, "four-search-peertube")
        marked.firstMatch.tap()
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45), "PeerTube video never played")
        app.swipeDown(velocity: .fast)   // To the mini-player, back to the results.
        XCTAssertTrue(app.otherElements["miniplayer"].waitForExistence(timeout: 10), "Player didn't dock")

        // The same field, back on YouTube: unmarked results, and one plays.
        network.buttons["YouTube"].tap()
        let youTube = results.buttons.matching(NSPredicate(format: "label != '' AND NOT label CONTAINS 'From PeerTube'"))
        XCTAssertTrue(youTube.firstMatch.waitForExistence(timeout: 30), "No YouTube results")
        youTube.firstMatch.tap()
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45), "YouTube video never played")
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

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }
}
