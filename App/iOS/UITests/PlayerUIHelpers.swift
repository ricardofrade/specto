import XCTest

extension XCUIApplication {
    /// Settings is a sheet (opened by the gear, or by onboarding's Add Instance): close it to get
    /// back to the tabs. Nothing happens when it isn't open.
    @MainActor
    func closeSettings() {
        let done = buttons["settings.done"]
        // Done is on Settings' first page: go back from any page pushed on it.
        for _ in 0..<3 where !done.waitForExistence(timeout: 2) {
            let back = navigationBars.buttons["BackButton"].firstMatch
            guard back.exists else { break }
            back.tap()
        }
        if done.exists { done.tap() }
    }

    /// A control over the video (PiP, AirPlay, Settings). They fade during playback, so tap the
    /// video first when it isn't showing.
    @MainActor
    func playerControl(_ identifier: String) -> XCUIElement {
        let control = buttons[identifier]
        if !(control.exists && control.isHittable) {
            otherElements["watch.surface"].tap()
            _ = control.waitForExistence(timeout: 3)
        }
        return control
    }

    /// The "…" menu under the title (audio only, casting, a link at the current time), then one
    /// of its items.
    @MainActor
    func chooseFromMoreMenu(_ item: String, file: StaticString = #filePath, line: UInt = #line) {
        let more = buttons["watch.more"]
        for _ in 0..<3 where !more.isHittable { swipeUp() }
        more.tap()
        let button = buttons[item]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "No \(item) in the … menu", file: file, line: line)
        button.tap()
    }
}
