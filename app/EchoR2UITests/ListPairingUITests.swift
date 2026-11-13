import XCTest

@MainActor
final class ListPairingUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false; mockScenario(["autoPair": "ok", "pushTest": "envError"]) }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func testAutoPairFirstLaunch() {
        let app = launchApp(token: nil)
        XCTAssertTrue(el(app, "sessions.row.\(HUB_RUNNING)").waitForExistence(timeout: 10))
    }

    func testAutoPairDeniedFallsBackToCode() {
        mockScenario(["autoPair": "deny"])
        let app = launchApp(token: nil)
        let code = app.textFields["pair.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        code.tap()
        code.typeText("abcd-2345")
        XCTAssertEqual(code.value as? String, "ABCD2345")
        app.buttons["pair.submit"].tap()
        XCTAssertTrue(el(app, "sessions.row.\(HUB_RUNNING)").waitForExistence(timeout: 10))
    }

    func testListSummaryAndOther() {
        let app = launchApp()
        XCTAssertTrue(el(app, "sessions.row.\(HUB_RUNNING)").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Refactor the auth middleware"].exists)
        XCTAssertFalse(el(app, "sessions.row.\(NOISE_P)").isHittable)
        el(app, "sessions.other.toggle").tap()
        XCTAssertTrue(el(app, "sessions.row.\(NOISE_P)").waitForExistence(timeout: 5))
    }

    func testPushTestShowsPlainError() {
        let app = launchApp()
        XCTAssertTrue(el(app, "sessions.row.\(HUB_RUNNING)").waitForExistence(timeout: 10))
        app.buttons["sessions.settings"].tap()
        let t = app.buttons["settings.push.test"]
        XCTAssertTrue(t.waitForExistence(timeout: 5))
        t.tap()
        let r = app.staticTexts["settings.push.result"]
        XCTAssertTrue(r.waitForExistence(timeout: 5))
        XCTAssertTrue(r.label.contains("Sandbox & Production"), r.label)
    }
}
