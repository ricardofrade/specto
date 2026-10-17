import XCTest

/// ADR 0005: a video AVPlayer can play as well as mpv plays in AVPlayer, and leaving the app
/// starts Picture-in-Picture by itself. PiP needs an iPad simulator or a device; use one whose
/// video height is at most 1080p-class (an 11-inch iPad), or VP9 1440p rightly stays in mpv.
final class AutoPictureInPictureUITests: XCTestCase {
    @MainActor
    func testLeavingTheAppStartsPictureInPicture() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("Picture-in-Picture isn't supported in the iPhone simulator")
        }
        let app = XCUIApplication()
        // Blender: its uploads have H.264 and AAC renditions.
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
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45), "Never played")
        let value = surface.value as? String ?? ""
        XCTAssertTrue(value.hasPrefix("playing avPlayer "), "Expected AVPlayer for an H.264 video: \(value)")
        sleep(3)

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let pip = springboard.windows["PIP-SBInteractionPassThroughView"]
        let started = pip.waitForExistence(timeout: 10)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "after-home"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(started, "Picture-in-Picture didn't start when leaving the app")
        sleep(4)

        // Back in the app: the video returns inline and keeps playing.
        app.activate()
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing avPlayer '", 15), "Not playing after returning")
        XCTAssertTrue(wait(pip, "exists == false", 10), "PiP window stayed after returning")
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }
}
