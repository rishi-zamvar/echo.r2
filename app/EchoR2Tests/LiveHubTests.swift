import XCTest

final class LiveHubTests: XCTestCase {
    /// GET /health only; skips if the loopback hub is not running.
    func testHealth() async throws {
        let c = HubClient(base: URL(string: "http://127.0.0.1:8790")!, token: nil)
        do {
            let h = try await c.health()
            XCTAssertEqual(h.protocolVersion, 1)
        } catch HubError.transport(let m) {
            throw XCTSkip("hub unreachable: \(m)")
        }
    }
}
