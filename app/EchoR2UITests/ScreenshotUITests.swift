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

        app.buttons["New session"].firstMatch.tap()
        sleep(2)
        shot("new-session")
        app.buttons["Cancel"].firstMatch.tap()
        sleep(1)

        app.buttons["sessions.settings"].tap()
        sleep(2)
        shot("settings")
    }
}
