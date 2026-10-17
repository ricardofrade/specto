import XCTest

/// Settings → Instances shows each instance's reachability and latency.
final class InstanceHealthUITests: XCTestCase {
    @MainActor
    func testInstanceRowShowsOnlineWithLatency() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["settings.instances"].firstMatch.tap()
        let row = app.descendants(matching: .any)["instance.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "No instance row")
        let online = NSPredicate(format: "label CONTAINS 'Online · ' AND label CONTAINS 'ms'")
        let result = XCTWaiter().wait(for: [expectation(for: online, evaluatedWith: row)], timeout: 20)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "instances"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(result, .completed, "Row says: \(row.label)")
    }
}
