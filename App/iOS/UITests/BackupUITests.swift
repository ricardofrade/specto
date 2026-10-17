import XCTest

/// Settings → Backup: exporting offers the system's save sheet. (Restoring is covered by
/// BackupTests; the document picker can't be driven reliably in UI tests.)
final class BackupUITests: XCTestCase {
    @MainActor
    func testExportOffersTheSaveSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedDemoFeed", "3"]
        app.launch()
        app.buttons["Settings"].firstMatch.tap()
        let backup = app.buttons["settings.backup"]
        for _ in 0..<6 where !backup.isHittable { app.swipeUp() }
        backup.tap()
        let export = app.buttons["settings.exportBackup"]
        for _ in 0..<6 where !export.isHittable { app.swipeUp() }
        XCTAssertTrue(export.waitForExistence(timeout: 5), "No Export Backup")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "backup-section"
        shot.lifetime = .keepAlways
        add(shot)
        export.tap()
        // The document browser in save mode: a Save/Move button and Cancel.
        let save = app.buttons.matching(NSPredicate(format: "label IN {'Save', 'Move'}")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "No save sheet")
        let sheet = XCTAttachment(screenshot: app.screenshot())
        sheet.name = "save-sheet"
        sheet.lifetime = .keepAlways
        add(sheet)
    }
}
