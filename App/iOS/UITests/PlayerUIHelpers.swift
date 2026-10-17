import XCTest

extension XCUIApplication {
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
