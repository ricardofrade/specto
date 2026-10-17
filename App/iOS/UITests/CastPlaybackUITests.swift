import XCTest

/// Casts a real video to a receiver on the network, then stops and resumes locally.
/// Plays on a real TV, so it runs only when `CAST_DEVICE` names one (e.g. "Chromecast").
final class CastPlaybackUITests: XCTestCase {
    @MainActor
    func testCastToReceiverAndBack() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let piped = environment["PIPED_URL"], let receiver = environment["CAST_DEVICE"] else {
            throw XCTSkip("Set PIPED_URL and CAST_DEVICE to cast to a real receiver")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"]
        app.launch()
        app.buttons["welcome.addInstance"].tap()   // Welcome → Add Instance, straight away.
        let field = app.textFields["instance.url"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(piped)
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Instance added"].waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
        app.closeSettings()   // Onboarding opened Instances inside Settings.
        app.buttons["Home"].firstMatch.tap()
        let list = app.scrollViews["feed.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 45))
        list.buttons.firstMatch.tap()

        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45), "Never played locally")
        sleep(10)   // Discovery.
        app.buttons["watch.more"].tap()
        let cast = app.buttons["Cast"]
        XCTAssertTrue(cast.waitForExistence(timeout: 15), "No Cast receivers discovered")
        cast.tap()
        let target = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", receiver)).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), "\(receiver) isn't listed")
        sleep(1)    // Taps during the menu's opening animation are ignored.
        target.tap()
        sleep(2)
        let picked = XCTAttachment(screenshot: app.screenshot())
        picked.name = "after-picking-receiver"
        picked.lifetime = .keepAlways
        add(picked)

        // The receiver loads the instance's stream itself; "Pause" means it reports PLAYING.
        let overlay = app.descendants(matching: .any)["watch.casting"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 10), "No casting overlay")
        let pause = overlay.buttons["Pause"]
        let playing = pause.waitForExistence(timeout: 45)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "casting"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(playing, "The receiver never reported playing")
        sleep(10)   // Let it play for a while on the TV.

        overlay.buttons["Stop Casting"].tap()
        XCTAssertTrue(wait(overlay, "exists == false", 10), "Casting overlay stayed")
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 20), "Local playback didn't resume")
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }
}
