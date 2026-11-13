import XCTest

/// Opt-in screen capture for design review. Skipped unless SCREENSHOT_DIR is set
/// (pass as TEST_RUNNER_SCREENSHOT_DIR to xcodebuild). SCREENSHOT_XXL=1 launches at XXL Dynamic Type.
@MainActor
final class ScreenshotUITests: XCTestCase {
    private var dir: String!
    private var suffix = ""
    private var extra: [String] = []

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let d = env["SCREENSHOT_DIR"], !d.isEmpty else { throw XCTSkip("SCREENSHOT_DIR not set") }
        dir = d
        if env["SCREENSHOT_XXL"] == "1" {
            suffix = "-xxl"
            extra = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"]
        }
        try FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
    }

    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(dir!)/\(name)\(suffix).png"))
    }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func testCaptureScreens() {
        mockScenario(["autoPair": "deny"])
        var app = launchApp(extra, token: nil)
        _ = app.textFields["pair.code"].waitForExistence(timeout: 10)
        sleep(1)
        shot("pairing")
        app.terminate()

        mockScenario(["autoPair": "ok"])
        app = launchApp(extra)
        _ = el(app, "sessions.row.\(HUB_RUNNING)").waitForExistence(timeout: 10)
        let other = el(app, "sessions.other.toggle")
        if other.waitForExistence(timeout: 3) {
            app.swipeUp()
            other.tap()
        }
        sleep(1)
        app.swipeDown()
        sleep(1)
        shot("list")

        app.buttons["sessions.new"].firstMatch.tap()
        sleep(2)
        shot("new-session")
        app.buttons["Cancel"].firstMatch.tap()
        sleep(1)

        app.buttons["sessions.settings"].tap()
        sleep(2)
        shot("settings")
    }

    private func openDetail(_ id: String) -> XCUIApplication {
        mockScenario(["autoPair": "ok"])
        let app = launchApp(extra)
        let row = el(app, "sessions.row.\(id)")
        if !row.waitForExistence(timeout: 10) || !row.isHittable {
            if el(app, "sessions.other.toggle").waitForExistence(timeout: 3) {
                app.swipeUp(); el(app, "sessions.other.toggle").tap(); sleep(1)
            }
        }
        row.tap()
        sleep(2)
        return app
    }

    /// Taps by accessibility identifier, falling back to the visible label (pre-05-09 builds).
    private func tap(_ app: XCUIApplication, _ id: String, label: String) {
        let e = el(app, id)
        if e.waitForExistence(timeout: 3) { e.tap() } else { app.buttons[label].firstMatch.tap() }
    }

    /// Session detail screens (05-09). Run the mock hub fresh: Continue here mutates its state.
    func testCaptureDetail() {
        var app = openDetail(HUB_RUNNING)
        shot("chat-running")
        if el(app, "detail.toolGroup").waitForExistence(timeout: 2) {
            el(app, "detail.toolGroup").firstMatch.tap(); sleep(1)
        }
        shot("chat-tools-expanded")
        tap(app, "detail.tab.terminal", label: "Terminal")
        sleep(2)
        shot("terminal-light")
        let menu = app.buttons["Session actions"].firstMatch
        if menu.waitForExistence(timeout: 2) {
            menu.tap()
            let dark = app.buttons["Dark terminal"].firstMatch
            if dark.waitForExistence(timeout: 2) { dark.tap(); sleep(1); shot("terminal-dark"); menu.tap(); app.buttons["Dark terminal"].firstMatch.tap() } else { app.tap() }
        }
        tap(app, "detail.tab.chat", label: "Chat")
        app.terminate()

        app = openDetail(HUB_STOPPED)
        shot("history-stopped")
        app.terminate()

        app = openDetail(EXT_EVEN)
        shot("watching-even")
        el(app, "detail.continueHere").tap()
        _ = app.alerts.firstMatch.waitForExistence(timeout: 5)
        shot("continue-refused")
        app.terminate()

        app = openDetail(EXT_CLI)
        el(app, "detail.continueHere").tap()
        _ = el(app, "detail.composer").waitForExistence(timeout: 10)
        sleep(2)
        shot("continue-cli")
    }
}
