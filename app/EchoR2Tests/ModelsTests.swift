import XCTest

func fixture(_ name: String) throws -> Data {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    return try Data(contentsOf: dir.appendingPathComponent(name))
}

final class ModelsTests: XCTestCase {
    func testHealth() throws {
        let h = try JSONDecoder().decode(Health.self, from: fixture("health.json"))
        XCTAssertEqual(h.protocolVersion, 1)
        XCTAssertFalse(h.hubName.isEmpty)
        XCTAssertNotNil(h.claude?.ok)
    }

    func testSessions() throws {
        let r = try JSONDecoder().decode(SessionsResponse.self, from: fixture("sessions.json"))
        XCTAssertFalse(r.sessions.isEmpty)
        XCTAssertNotNil(r.sessions[0].startedDate)
        let ext = #"{"id":"a","cwd":"/x/proj","state":"external","source":"external","label":"Even Terminal","title":"x"}"#
        let s = try JSONDecoder().decode(SessionInfo.self, from: Data(ext.utf8))
        XCTAssertTrue(s.isExternal)
        var t = s; t.title = ""
        XCTAssertEqual(t.displayTitle, "proj")
        XCTAssertEqual(s.displayTitle, "x")
    }

    func testRoots() throws {
        _ = try JSONDecoder().decode(RootsResponse.self, from: fixture("roots.json"))
        XCTAssertEqual(Root(root: "/a", dirs: ["b", "c"]).cwdOptions, ["/a", "/a/b", "/a/c"])
    }

    func testBaseURL() {
        XCTAssertEqual(HubClient.baseURL(from: "rishis-macbook-pro")?.absoluteString, "http://rishis-macbook-pro:8790")
        XCTAssertEqual(HubClient.baseURL(from: "100.125.215.102:8790")?.absoluteString, "http://100.125.215.102:8790")
        XCTAssertEqual(HubClient.baseURL(from: " host:9000 ")?.absoluteString, "http://host:9000")
        for bad in ["", "http://x", "a b", "host:abc", "host/path", "host:0", "host:70000"] {
            XCTAssertNil(HubClient.baseURL(from: bad), bad)
        }
    }

    func testErrorMap() {
        XCTAssertNil(HubError.map(status: 201, body: Data()))
        XCTAssertEqual(HubError.map(status: 401, body: Data()), .unauthorized)
        XCTAssertEqual(HubError.map(status: 403, body: Data(#"{"error":"forbidden"}"#.utf8)), .forbidden)
        XCTAssertEqual(HubError.map(status: 403, body: Data(#"{"error":"bad_code"}"#.utf8)), .server("bad_code", 403))
        XCTAssertEqual(HubError.map(status: 503, body: Data(#"{"error":"claude_unavailable"}"#.utf8)), .server("claude_unavailable", 503))
    }
}
