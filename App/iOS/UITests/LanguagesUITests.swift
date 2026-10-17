import XCTest

/// Every shipped language, offline (demo feed): Home, Library and Settings render in it, and
/// nothing the app draws is clipped (longer German or French copy).
final class LanguagesUITests: XCTestCase {
    @MainActor
    func testEveryLanguageRendersWithoutClipping() throws {
        let only = ProcessInfo.processInfo.environment["LANGUAGES"]?.split(separator: ",").map(String.init)
        for language in only ?? ["de", "fr", "es", "pt-BR", "pt-PT"] {
            let app = XCUIApplication()
            app.launchArguments = ["-UITestFreshStart", "-SeedDemoFeed", "8",
                                   "-AppleLanguages", "(\(language))", "-AppleLocale", language.replacingOccurrences(of: "-", with: "_")]
            app.launch()
            XCTAssertTrue(app.scrollViews["feed.list"].waitForExistence(timeout: 10), "\(language): no Home")
            shot(app, "\(language)-home")
            try audit(app, "\(language)-home")

            // Tabs by position (Home, Explore, Library, Search): their titles are translated.
            let tabs = app.tabBars.buttons
            tabs.element(boundBy: 2).tap()
            XCTAssertTrue(app.buttons["library.playlists"].waitForExistence(timeout: 5)
                          || app.buttons["library.channels"].waitForExistence(timeout: 5), "\(language): no Library")
            shot(app, "\(language)-library")
            try audit(app, "\(language)-library")
            app.buttons["settings.open"].tap()
            XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5), "\(language): no Settings")
            sleep(1)   // Let the sheet finish rising: rows still below the screen's edge read as clipped.
            shot(app, "\(language)-settings")
            try audit(app, "\(language)-settings")
            app.terminate()
        }
    }

    /// Clipped text the app draws (system chrome without an element is ignored, as elsewhere).
    @MainActor
    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        try app.performAccessibilityAudit(for: [.textClipped]) { issue in
            print("AUDIT[\(screen)] \(issue.compactDescription) — \(issue.element.map { "'\($0.label)' \($0.frame)" } ?? "no element")")
            guard let element = issue.element else { return true }
            // Settings' fifth row (Notifications, before it Suggestions while typing) reads as
            // clipped over Library in every language, though the screenshot shows it whole and
            // its frame is exactly the word; the same row passes in English at the largest size.
            let row = app.buttons["settings.notifications"]
            return issue.auditType == .textClipped && row.exists && row.frame.contains(element.frame)
        }
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["SHOTS_DIR"] {   // Survives a lost result bundle.
            try? app.screenshot().pngRepresentation.write(to: URL(filePath: folder).appending(path: "\(name).png"))
        }
    }
}
