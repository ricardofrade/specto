import XCTest

/// Widget and Shortcuts links: `dev.placeholder.specto://watch?v=<id>` opens and plays the video.
final class DeepLinkUITests: XCTestCase {
    @MainActor
    func testWatchLinkPlaysTheVideo() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped]
        app.launch()
        app.open(try XCTUnwrap(URL(string: "dev.placeholder.specto://watch?v=SVJiCL3K0j4")))
        let surface = app.otherElements["watch.surface"]
        XCTAssertTrue(XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "value BEGINSWITH 'playing '"),
                                                         evaluatedWith: surface)], timeout: 45) == .completed,
                      "The link didn't play the video")
    }
}
