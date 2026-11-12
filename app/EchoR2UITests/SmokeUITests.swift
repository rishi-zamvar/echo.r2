import XCTest

@MainActor
final class SmokeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testListLoadsFromMockHub() {
        let app = launchApp()
        XCTAssertTrue(app.descendants(matching: .any)["sessions.row.\(HUB_RUNNING)"].waitForExistence(timeout: 10))
    }
}
