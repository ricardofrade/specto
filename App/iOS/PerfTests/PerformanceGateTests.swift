import XCTest

/// Performance gates from CLAUDE.md. Simulator numbers are a regression trend only;
/// the gates themselves are measured on a ProMotion device.
final class PerformanceGateTests: XCTestCase {
    private let subsystem = "dev.placeholder.player.performance"
    private let category = "PointsOfInterest"

    override func setUp() {
        continueAfterFailure = false
    }

    /// Gate: cold launch to first rendered feed < 400 ms (signpost interval).
    @MainActor func testLaunchToFirstFeedFrame() {
        let metric = XCTOSSignpostMetric(subsystem: subsystem, category: category,
                                         name: "launch.firstFeedFrame")
        let app = XCUIApplication()
        measure(metrics: [metric, XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            app.launch()
            app.terminate()
        }
    }

    /// Gate: scroll hitch ratio < 5 ms/s over the real feed screen with 1,000 cached videos.
    @MainActor func testScrollHitchRatio() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedDemoFeed", "1000"]
        app.launch()
        let list = app.scrollViews["feed.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))

        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            list.swipeUp(velocity: .fast)
            stopMeasuring()
            list.swipeDown(velocity: .fast)
        }
    }

    @MainActor func testFrameRateScreenRuns() {
        let app = XCUIApplication()
        app.launchArguments = ["-Harness", "frameRate"]
        app.launch()
        let reading = app.staticTexts["perf.fps"]
        XCTAssertTrue(reading.waitForExistence(timeout: 10))
        // The label switches from the placeholder once a full second has been measured.
        let measured = NSPredicate(format: "label ENDSWITH ' fps' AND NOT (label BEGINSWITH '–')")
        expectation(for: measured, evaluatedWith: reading)
        waitForExpectations(timeout: 5)
        print("Frame rate reading: \(reading.label)")
    }
}
