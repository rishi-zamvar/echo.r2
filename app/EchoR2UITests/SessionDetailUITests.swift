import XCTest

@MainActor
final class SessionDetailUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func open(_ id: String) -> XCUIApplication {
        let app = launchApp()
        let row = app.descendants(matching: .any)["sessions.row.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        return app
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    /// Chat bubbles are one VoiceOver element labelled "You: …" / "Claude: …" (05-09).
    private func labelled(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    func testStoppedSessionShowsHistory() {
        let app = open(HUB_STOPPED)
        XCTAssertTrue(labelled(app, "You: list the files in this repo").waitForExistence(timeout: 10))
        XCTAssertTrue(el(app, "detail.composer").exists)
    }

    func testSendInHubSession() {
        let app = open(HUB_RUNNING)
        let composer = el(app, "detail.composer")
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("hello")
        el(app, "detail.send").tap()
        XCTAssertTrue(labelled(app, "Claude: echo: hello").waitForExistence(timeout: 5))
    }

    func testWorkingIndicatorAndToolGroup() {
        let app = open(HUB_RUNNING)
        XCTAssertTrue(el(app, "detail.working").waitForExistence(timeout: 10))
        let group = el(app, "detail.toolGroup")
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        XCTAssertTrue(group.label.contains("Used 1 tool, collapsed"))
        XCTAssertFalse(labelled(app, "Bash: ls -la").exists)
        group.tap()
        XCTAssertTrue(labelled(app, "Bash: ls -la").waitForExistence(timeout: 3))
    }

    func testContinueHereRefusedForEvenTerminal() {
        let app = open(EXT_EVEN)
        let header = el(app, "detail.watchingHeader")
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(header.label.contains("Even Terminal"))
        el(app, "detail.continueHere").tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.firstMatch.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Even Terminal'")).firstMatch.exists)
    }

    func testContinueHereTakesOver() {
        let app = open(EXT_CLI)
        let btn = el(app, "detail.continueHere")
        XCTAssertTrue(btn.waitForExistence(timeout: 10))
        btn.tap()
        XCTAssertTrue(el(app, "detail.composer").waitForExistence(timeout: 10))
    }

    /// Opt-in: needs a real hub session. See 05-06 plan Task 3.
    func testLiveHubSend() throws {
        guard let id = ProcessInfo.processInfo.environment["LIVE_HUB_SESSION"] else { throw XCTSkip("LIVE_HUB_SESSION not set") }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestHubHost", "127.0.0.1:8790", "-uiTestToken", "live"]
        app.launch()
        let row = el(app, "sessions.row.\(id)")
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        let composer = el(app, "detail.composer")
        XCTAssertTrue(composer.waitForExistence(timeout: 20))
        composer.tap()
        composer.typeText("Reply with exactly: echo-e2e-ok")
        el(app, "detail.send").tap()
        // The user bubble holds the longer prompt, so an exact-label match is the assistant reply.
        let reply = labelled(app, "Claude: echo-e2e-ok")
        XCTAssertTrue(reply.waitForExistence(timeout: 90))
    }
}
