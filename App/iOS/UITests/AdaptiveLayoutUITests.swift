import XCTest

/// M3: resizing never interrupts playback, and every screen passes the accessibility audit.
final class AdaptiveLayoutUITests: XCTestCase {
    private let channel = "UCSMOQeBJ2RAnuFungnQOxLg"

    /// XCUITest can't resize windows, so rotation stands in: it drives the same size-driven
    /// layout changes (compact ↔ band ↔ side panel) and surface re-attachment.
    @MainActor
    func testRotatingDuringPlaybackNeverStalls() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedSubscriptions", channel]
        app.launch()
        app.buttons["Add Instance"].firstMatch.tap()      // Feed's empty state → Instances screen.
        XCTAssertTrue(app.navigationBars["Instances"].waitForExistence(timeout: 5))
        app.buttons["Add Instance"].firstMatch.tap()
        let field = app.textFields["instance.url"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(piped)
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Instance added"].waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
        app.buttons["Subscriptions"].firstMatch.tap()
        let list = app.scrollViews["feed.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 45))
        list.buttons.firstMatch.tap()

        let surface = app.otherElements["watch.surface"]
        let playing = NSPredicate(format: "value BEGINSWITH 'playing '")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: playing, evaluatedWith: surface)], timeout: 45), .completed)

        let orientations: [UIDeviceOrientation] = [.landscapeLeft, .portrait, .landscapeRight, .portrait,
                                                   .landscapeLeft, .portrait]
        var last = try seconds(surface)
        for orientation in orientations {
            XCUIDevice.shared.orientation = orientation
            sleep(2)
            XCTAssertTrue(surface.exists, "Surface missing after rotating to \(orientation.rawValue)")
            let state = surface.value as? String ?? ""
            XCTAssertTrue(state.hasPrefix("playing "), "Not playing after rotating to \(orientation.rawValue): \(state)")
            let now = try seconds(surface)
            XCTAssertGreaterThan(now, last, "Playback stalled across rotation to \(orientation.rawValue)")
            last = now
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "after-rotations"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testScreensPassTheAccessibilityAuditAtLargestTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedDemoFeed", "40",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.scrollViews["feed.list"].waitForExistence(timeout: 10))
        try audit(app, "feed", [.dynamicType, .sufficientElementDescription, .hitRegion, .textClipped])
        app.buttons["Settings"].firstMatch.tap()
        try audit(app, "settings", [.dynamicType, .sufficientElementDescription, .hitRegion, .textClipped])
        app.buttons["Search"].firstMatch.tap()
        try audit(app, "search", [.dynamicType, .sufficientElementDescription, .hitRegion, .textClipped])
    }

    /// Prints every issue with its element, so a failure says exactly what to fix.
    @MainActor
    private func audit(_ app: XCUIApplication, _ screen: String, _ types: XCUIAccessibilityAuditType) throws {
        try app.performAccessibilityAudit(for: types) { issue in
            print("AUDIT[\(screen)] \(issue.compactDescription) — \(issue.element.map { "\($0.elementType.rawValue) '\($0.label)' id=\($0.identifier)" } ?? "no element")")
            // Dynamic Type issues with no element come from system chrome the app doesn't draw
            // (iPad's floating tab bar keeps its size); everything the app renders must pass.
            return issue.auditType == .dynamicType && issue.element == nil
        }
    }

    @MainActor
    private func seconds(_ surface: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(surface.value as? String)
        return try XCTUnwrap(Int(value.split(separator: " ").last ?? ""))
    }
}
