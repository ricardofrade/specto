import XCTest

/// iPhone Duo (or any device): reports the fold's geometry and screenshots Home, so layouts that
/// follow the crease can be checked on the simulator. Skipped where there's no fold.
final class DuoGeometryUITests: XCTestCase {
    @MainActor
    func testReportsTheFold() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedDemoFeed", "12", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.scrollViews["feed.list"].waitForExistence(timeout: 10))
        let state = app.descendants(matching: .any)["fold.state"]
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        print("FOLD: \(state.value as? String ?? "?") window=\(app.windows.firstMatch.frame)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "duo-home"
        shot.lifetime = .keepAlways
        add(shot)
        if let folder = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? app.screenshot().pngRepresentation.write(to: URL(filePath: folder).appending(path: "duo-home.png"))
        }
    }
}
