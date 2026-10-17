import XCTest

/// The description's links are tappable with their full addresses, and More shows the whole text.
final class DescriptionUITests: XCTestCase {
    @MainActor
    func testLinksAndMore() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)"]
        app.launch()
        // Big Buck Bunny: its description links to the Blender Studio project page.
        app.open(try XCTUnwrap(URL(string: "dev.placeholder.specto://watch?v=aqz-KE-bpKQ")))
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(wait(surface, "value BEGINSWITH 'playing '", 45), "Never played")

        let description = app.descendants(matching: .any)["watch.description"]
        for _ in 0..<4 where !description.exists { app.swipeUp() }
        XCTAssertTrue(description.waitForExistence(timeout: 10), "No description")
        // Short descriptions show in full, without More.
        if app.buttons["watch.descriptionMore"].exists { app.buttons["watch.descriptionMore"].tap() }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "description"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Piped shortens the address it shows ("…/b..."); the link carries the whole one.
        XCTAssertTrue(description.links.firstMatch.waitForExistence(timeout: 5), "No links in the description")
        XCTAssertTrue(description.label.contains("https://studio.blender.org/projects/big-buck-bunny/"),
                      "The address is shortened: \(description.label)")
        XCTAssertTrue(app.staticTexts["Blender"].exists || app.buttons["watch.channel"].label.contains("Blender"),
                      "The channel name didn't arrive with the details")
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }
}
