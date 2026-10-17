import XCTest

/// M6 against a real Piped instance: queueing from Watch, and (Debug builds) the queued video's
/// audio downloading for offline listening.
final class ListeningUITests: XCTestCase {
    @MainActor
    func testQueueAndOfflineDownload() throws {
        guard let piped = ProcessInfo.processInfo.environment["PIPED_URL"] else {
            throw XCTSkip("Set PIPED_URL to run against a real instance")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedSubscriptions", "UCSMOQeBJ2RAnuFungnQOxLg"]
        app.launch()
        app.buttons["Add Instance"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Instances"].waitForExistence(timeout: 5))
        app.buttons["Add Instance"].firstMatch.tap()
        let field = app.textFields["instance.url"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(piped)
        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Instance added"].waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
        app.buttons["Home"].firstMatch.tap()
        let list = app.scrollViews["feed.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 45))
        list.buttons.firstMatch.tap()

        let queue = app.buttons["watch.queue"]
        XCTAssertTrue(queue.waitForExistence(timeout: 20))
        XCTAssertEqual(queue.label, "Add to Queue")
        queue.tap()
        XCTAssertTrue(wait(queue, "label == 'Queued'", 5), "Queue button didn't toggle")

        app.swipeDown(velocity: .fast)
        #if DEBUG
        // Debug builds (like the app's) include OFFLINE_DOWNLOADS; Release builds never do.
        // Settings reads usage on appear: revisit until the download lands.
        let used = app.descendants(matching: .any)["settings.offlineUsed"]
        let deadline = Date.now.addingTimeInterval(90)
        var landed = false
        var first = true
        while Date.now < deadline, !landed {
            if !first {
                app.buttons["Home"].firstMatch.tap()   // Leave so Settings re-reads usage.
                sleep(5)
            }
            first = false
            app.buttons["Settings"].firstMatch.tap()
            // Onboarding left Instances pushed on the Settings stack.
            if app.buttons["BackButton"].exists { app.buttons["BackButton"].tap() }
            for _ in 0..<4 where !used.exists { app.swipeUp() }   // Form only builds visible rows.
            // The value reads "Zero KB" until the file lands, then e.g. "3.4 MB".
            if used.exists, ((used.value as? String) ?? "").range(of: #"[1-9][\d.,]* [KMG]B"#, options: .regularExpression) != nil {
                landed = true
            }
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "offline-usage"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(used.exists, "No offline usage row in Settings")
        XCTAssertTrue(landed, "Queued audio didn't download: \(String(describing: used.value))")
        #endif
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }
}
