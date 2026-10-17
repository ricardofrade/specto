import XCTest

/// Signing in with a username and password: Piped from its row in Settings → Instances, and
/// YT Zero at its pairing step. Needs the instance URLs and the test account
/// (`INSTANCE_USERNAME`/`INSTANCE_PASSWORD`, from the environment only).
final class AccountSignInUITests: XCTestCase {
    private let environment = ProcessInfo.processInfo.environment

    @MainActor
    func testPipedSignInBringsTheAccountsSubscriptions() throws {
        guard let piped = environment["PIPED_URL"], let user = environment["INSTANCE_USERNAME"],
              let password = environment["INSTANCE_PASSWORD"] else { throw XCTSkip("Needs PIPED_URL and the test account") }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-SeedInstance", piped, "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["settings.open"].tap()
        app.buttons["settings.instances"].tap()
        let row = app.descendants(matching: .any)["instance.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Sign In…"].waitForExistence(timeout: 5), "No Sign In for Piped")
        app.buttons["Sign In…"].tap()
        let username = app.textFields["signIn.username"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        username.tap()
        username.typeText(user)
        let field = app.secureTextFields["signIn.password"]
        field.tap()
        field.typeText(password)
        app.buttons["signIn.submit"].tap()
        XCTAssertTrue(wait(row, "label CONTAINS 'Your subscriptions'", 30), "Not signed in: \(row.label)")
        shot(app, "80-signed-in")

        app.closeSettings()
        XCTAssertTrue(app.scrollViews["feed.list"].waitForExistence(timeout: 60), "The account's feed didn't come")
        shot(app, "81-account-home")
    }

    @MainActor
    func testYTZeroSignInWithPassword() throws {
        guard environment["ACCOUNT_YTZERO"] == "1", let ytZero = environment["YTZERO_URL"],
              let user = environment["INSTANCE_USERNAME"], let password = environment["INSTANCE_PASSWORD"] else {
            throw XCTSkip("Needs ACCOUNT_YTZERO=1, YTZERO_URL and the test account (each run makes a device session)")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestFreshStart", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["welcome.addInstance"].tap()
        let url = app.textFields["instance.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        url.typeText(ytZero)
        app.buttons["Next"].tap()
        let username = app.textFields["pairing.username"]
        XCTAssertTrue(username.waitForExistence(timeout: 20), "No pairing step")
        shot(app, "82-ytzero-pairing")
        username.tap()
        username.typeText(user)
        let field = app.secureTextFields["pairing.password"]
        field.tap()
        field.typeText(password)
        app.buttons["pairing.signIn"].tap()
        XCTAssertTrue(app.staticTexts["Instance added"].waitForExistence(timeout: 30), "YT Zero sign-in failed")
    }

    @MainActor
    private func wait(_ element: XCUIElement, _ format: String, _ timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: format), evaluatedWith: element)],
                         timeout: timeout) == .completed
    }

    @MainActor
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? app.screenshot().pngRepresentation.write(to: URL(filePath: folder).appending(path: "\(name).png"))
        }
    }
}
