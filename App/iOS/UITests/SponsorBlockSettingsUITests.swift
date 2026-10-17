import XCTest

/// Offline: Settings → SponsorBlock sets each category, and the choice survives a relaunch.
final class SponsorBlockSettingsUITests: XCTestCase {
    @MainActor
    func testCategoryChoiceIsKept() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedDemoFeed", "3", "-AppleLanguages", "(en)"]
        app.launch()
        openCategories(app)
        // Settings outlive the app between runs: start from a known choice.
        let intro = app.buttons["sponsorBlock.intro"]
        choose(app, intro, "Don't skip")
        choose(app, intro, "Show a Skip button")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "sponsorblock"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Off hides the categories.
        app.switches["sponsorBlock.enabled"].switches.firstMatch.tap()
        XCTAssertFalse(intro.waitForExistence(timeout: 2))
        app.switches["sponsorBlock.enabled"].switches.firstMatch.tap()

        app.terminate()
        app.launchArguments = ["-SeedDemoFeed", "3", "-AppleLanguages", "(en)"]
        app.launch()
        openCategories(app)
        XCTAssertTrue(app.buttons["sponsorBlock.intro"].label.contains("Show a Skip button"))
        choose(app, app.buttons["sponsorBlock.intro"], "Don't skip")   // Leave the default behind.
    }

    @MainActor
    private func choose(_ app: XCUIApplication, _ picker: XCUIElement, _ option: String) {
        picker.tap()
        let item = app.buttons[option]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "No \(option) option")
        item.tap()
        XCTAssertTrue(picker.label.contains(option), "Picker shows \(picker.label), not \(option)")
    }

    @MainActor
    private func openCategories(_ app: XCUIApplication) {
        app.buttons["Settings"].firstMatch.tap()
        let link = app.buttons["settings.sponsorBlock"]
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        link.tap()
        XCTAssertTrue(app.buttons["sponsorBlock.intro"].waitForExistence(timeout: 5), "No SponsorBlock categories")
    }
}
