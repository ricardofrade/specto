import XCTest

/// The iPhone Duo's own layouts, on a simulated fold (`-SimulateFold`): a simulator can't change
/// pose from the command line, so this checks the layouts, and the device checks the hardware.
/// Run on an iPad simulator, whose size is close to the Duo opened.
final class DuoLayoutsUITests: XCTestCase {
    /// Open flat: the player docks beside the tabs, and another video swaps in without leaving
    /// the list.
    @MainActor
    func testOpenFlatWatchesBesideBrowsing() throws {
        let app = try launch(["-SimulateFold", "flat", "-FoldAxis", "vertical"])
        let list = app.scrollViews["feed.list"]
        let videos = list.buttons.matching(NSPredicate(format: "identifier != 'feed.channel' AND identifier != 'feed.allChannels'"))
        videos.element(boundBy: 0).tap()
        let pane = app.descendants(matching: .any)["split.player"]
        XCTAssertTrue(pane.waitForExistence(timeout: 10), "No player beside the tabs")
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45))
        XCTAssertTrue(list.exists && list.isHittable, "Browsing should stay on the other half")
        shot(app, "50-duo-open")

        let first = surface.value as? String ?? ""
        videos.element(boundBy: 2).tap()
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing ' AND NOT (value == %@)", 45, first) , "Didn't swap videos")
        XCTAssertTrue(list.exists, "The list left when the video changed")
        shot(app, "51-duo-open-swapped")
        app.buttons["watch.close"].tap()
        XCTAssertFalse(pane.waitForExistence(timeout: 2))
    }

    /// Tabletop: the picture alone above the crease, the deck with the controls below.
    @MainActor
    func testTabletopPutsTheControlsOnTheDeck() throws {
        let app = try launch(["-SimulateFold", "bent", "-FoldAxis", "horizontal"])
        app.scrollViews["feed.list"].buttons.matching(NSPredicate(format: "identifier != 'feed.channel' AND identifier != 'feed.allChannels'")).element(boundBy: 0).tap()
        let deck = app.descendants(matching: .any)["watch.tabletopDeck"]
        XCTAssertTrue(deck.waitForExistence(timeout: 10), "No tabletop deck")
        XCTAssertTrue(wait(app.otherElements["watch.surface"], "value BEGINSWITH 'playing '", 45))
        sleep(3)
        shot(app, "52-duo-tabletop")
    }

    /// Book: the video beside the details.
    @MainActor
    func testBookPutsTheDetailsBesideTheVideo() throws {
        let app = try launch(["-SimulateFold", "bent", "-FoldAxis", "vertical"])
        app.scrollViews["feed.list"].buttons.matching(NSPredicate(format: "identifier != 'feed.channel' AND identifier != 'feed.allChannels'")).element(boundBy: 0).tap()
        XCTAssertTrue(wait(app.otherElements["watch.surface"], "value BEGINSWITH 'playing '", 45))
        sleep(3)
        shot(app, "53-duo-book")
    }

    @MainActor
    private func launch(_ fold: [String]) throws -> XCUIApplication {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)",
                               "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"] + fold
        app.launch()
        XCTAssertTrue(app.scrollViews["feed.list"].waitForExistence(timeout: 45))
        return app
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval, _ args: CVarArg...) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format, argumentArray: args), evaluatedWith: element)],
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
