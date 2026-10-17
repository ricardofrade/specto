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

        // Save to Playlist sheet, then Library → Playlists.
        let video = app.scrollViews["feed.list"].buttons.firstMatch
        video.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Save to Playlist…"].waitForExistence(timeout: 5))
        app.buttons["Save to Playlist…"].tap()
        XCTAssertTrue(app.buttons["save.new"].waitForExistence(timeout: 5))
        try audit(app, "save-sheet", [.dynamicType, .sufficientElementDescription, .hitRegion, .textClipped],
                  wrapsWithoutClipping: ["Watch Later", "0 videos", "New Playlist"])
        app.buttons.matching(identifier: "save.playlist").firstMatch.tap()   // Watch Later.
        app.buttons["Done"].tap()
        app.buttons["Library"].firstMatch.tap()
        let playlists = app.buttons["library.playlists"]
        for _ in 0..<6 where !playlists.exists { app.swipeUp() }   // Lazy list, very large text.
        XCTAssertTrue(playlists.waitForExistence(timeout: 5))
        playlists.tap()
        XCTAssertTrue(app.buttons["playlists.watchLater"].waitForExistence(timeout: 5))
        try audit(app, "playlists", [.dynamicType, .sufficientElementDescription, .hitRegion, .textClipped],
                  wrapsWithoutClipping: ["New Playlist"])

        app.buttons["Home"].firstMatch.tap()   // The gear is on each tab's first screen.
        app.buttons["Settings"].firstMatch.tap()
        try audit(app, "settings", [.dynamicType, .sufficientElementDescription, .hitRegion, .textClipped])
        app.closeSettings()
        // Search last: on iOS 26 the search tab collapses the tab bar, so no tab is left to tap.
        app.buttons["Search"].firstMatch.tap()
        try audit(app, "search", [.dynamicType, .sufficientElementDescription, .hitRegion, .textClipped])
    }

    /// The screens that need a real instance: Explore (Home with no subscriptions), and the
    /// Watch screen with its floating controls and settings menu.
    @MainActor
    func testLiveScreensPassTheAccessibilityAuditAtLargestTextSize() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let trending = app.descendants(matching: .any)["feed.trending"].firstMatch
        XCTAssertTrue(trending.waitForExistence(timeout: 45), "No trending videos on an empty Home")
        try audit(app, "explore", [.dynamicType, .sufficientElementDescription, .hitRegion, .textClipped])

        trending.tap()
        let surface = app.otherElements["watch.surface"]
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "value BEGINSWITH 'playing '"),
                                                          evaluatedWith: surface)], timeout: 45), .completed)
        _ = app.playerControl("watch.settings")
        try audit(app, "watch", [.dynamicType, .sufficientElementDescription, .hitRegion, .textClipped])
        app.playerControl("watch.settings").tap()   // The audit outlasts the controls: reveal again.
        XCTAssertTrue(app.buttons["Playback Speed"].waitForExistence(timeout: 5), "Settings menu didn't open")
        try audit(app, "watch-settings", [.dynamicType, .sufficientElementDescription, .hitRegion, .textClipped])
    }

    /// Prints every issue with its element, so a failure says exactly what to fix.
    @MainActor
    /// - Parameter wrapsWithoutClipping: texts the audit reports as clipped that the attached
    ///   screenshot shows whole. The audit misreads wrapped text in some List rows (the Save
    ///   sheet's, "New Playlist"), while the same text passes elsewhere. Check the screenshot
    ///   before adding to it.
    private func audit(_ app: XCUIApplication, _ screen: String, _ types: XCUIAccessibilityAuditType,
                       wrapsWithoutClipping: Set<String> = []) throws {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "audit-\(screen)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["SHOTS_DIR"] {   // Survives a lost result bundle.
            try? app.screenshot().pngRepresentation.write(to: URL(filePath: folder).appending(path: "audit-\(screen).png"))
        }
        try app.performAccessibilityAudit(for: types) { issue in
            print("AUDIT[\(screen)] \(issue.compactDescription) — \(issue.element.map { "\($0.elementType.rawValue) '\($0.label)' id=\($0.identifier)" } ?? "no element")")
            // System chrome the app doesn't draw keeps its own size: elements with no element
            // (iPad's floating tab bar), navigation bar buttons (a sheet's Done) and the search
            // field's prompt. Everything the app renders must pass.
            guard let element = issue.element else { return issue.auditType == .dynamicType }
            if issue.auditType == .textClipped, wrapsWithoutClipping.contains(element.label) { return true }
            if element.elementType == .searchField { return true }
            let bar = app.navigationBars.firstMatch
            return issue.auditType == .dynamicType && bar.exists && bar.frame.contains(element.frame)
        }
    }

    @MainActor
    private func seconds(_ surface: XCUIElement) throws -> Int {
        let value = try XCTUnwrap(surface.value as? String)
        return try XCTUnwrap(Int(value.split(separator: " ").last ?? ""))
    }
}
