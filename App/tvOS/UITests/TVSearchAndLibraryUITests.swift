import XCTest

/// Search and Library on Apple TV against a real instance, driven with the Siri Remote only.
final class TVSearchAndLibraryUITests: XCTestCase {
    @MainActor private var remote: XCUIRemote { .shared }

    /// Typing searches (no return key on the TV keyboard); results appear without submitting.
    @MainActor
    func testSearchAsYouType() throws {
        let app = try launch()
        XCTAssertTrue(moveToTab(app, "Search"), "Couldn't reach the Search tab")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "No search field")
        // Focus the field and select it: that brings up its keyboard, which typing needs.
        for _ in 0..<3 where !field.hasFocus {
            remote.press(.up)
            usleep(400_000)
        }
        if !field.hasFocus { remote.press(.down) }
        remote.press(.select)
        sleep(1)
        attach(app, "keyboard")
        app.typeText("blender")
        let result = app.descendants(matching: .any).matching(identifier: "tv.search.result").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30), "No results while typing")
        attach(app, "search")
    }

    /// A watched video shows in Library's Continue Watching and History.
    @MainActor
    func testLibraryShowsWhatWasWatched() throws {
        let app = try launch(subscribed: true)
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 60), "The billboard never loaded")
        remote.press(.down)
        sleep(1)
        remote.press(.select)
        let player = app.otherElements["tv.player"]
        XCTAssertTrue(wait(player, "value BEGINSWITH 'playing '", 60), "Never played")
        sleep(8)    // Past the 5 s a video needs to count as started.
        remote.press(.menu)
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))

        XCTAssertTrue(moveToTab(app, "Library"), "Couldn't reach the Library tab")
        XCTAssertTrue(app.staticTexts["Continue Watching"].waitForExistence(timeout: 10), "No Continue Watching")
        XCTAssertTrue(app.staticTexts["History"].exists, "No History")
        attach(app, "library")
    }

    @MainActor
    private func launch(subscribed: Bool = false) throws -> XCUIApplication {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped]
            + (subscribed ? ["-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"] : [])
        app.launch()
        return app
    }

    /// Up to the tab bar, then sideways until the tab has focus (tvOS selects a focused tab).
    @MainActor
    private func moveToTab(_ app: XCUIApplication, _ name: String) -> Bool {
        for _ in 0..<4 { remote.press(.up) }
        let tab = app.tabBars.buttons[name]
        guard tab.waitForExistence(timeout: 10) else { return false }
        for _ in 0..<6 where !tab.hasFocus {
            remote.press(.right)
            usleep(400_000)
        }
        for _ in 0..<6 where !tab.hasFocus {
            remote.press(.left)
            usleep(400_000)
        }
        guard tab.hasFocus else { return false }
        remote.press(.down)
        sleep(1)
        return true
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }
}
