import XCTest

/// Every shipped language, offline (demo feed): Home, Library and Settings render in it, and
/// nothing the app draws is clipped (longer German or French copy).
final class LanguagesUITests: XCTestCase {
    @MainActor
    func testEveryLanguageRendersWithoutClipping() throws {
        for language in ["de", "fr", "es", "pt-BR", "pt-PT"] {
            let app = XCUIApplication()
            app.launchArguments = ["-UITestFreshStart", "-SeedDemoFeed", "8",
                                   "-AppleLanguages", "(\(language))", "-AppleLocale", language.replacingOccurrences(of: "-", with: "_")]
            app.launch()
            XCTAssertTrue(app.scrollViews["feed.list"].waitForExistence(timeout: 10), "\(language): no Home")
            shot(app, "\(language)-home")
            try audit(app, "\(language)-home")

            // Tabs by position: their titles are translated.
            let tabs = app.tabBars.buttons
            tabs.element(boundBy: 1).tap()
            shot(app, "\(language)-library")
            tabs.element(boundBy: 2).tap()
            XCTAssertTrue(app.collectionViews.firstMatch.waitForExistence(timeout: 5), "\(language): no Settings")
            shot(app, "\(language)-settings")
            try audit(app, "\(language)-settings")
            app.terminate()
        }
    }

    /// Clipped text the app draws (system chrome without an element is ignored, as elsewhere).
    @MainActor
    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        try app.performAccessibilityAudit(for: [.textClipped]) { issue in
            print("AUDIT[\(screen)] \(issue.compactDescription) — \(issue.element.map { "'\($0.label)'" } ?? "no element")")
            return issue.element == nil
        }
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
