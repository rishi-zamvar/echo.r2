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

    private func sess(_ id: String, _ state: String, source: String = "hub", at: String? = nil) -> SessionInfo {
        SessionInfo(id: id, cwd: "/x/\(id)", pid: nil, state: state, source: source, startedAt: at, label: nil, title: nil)
    }

    func testChipAndTitle() {
        XCTAssertEqual(sess("a", "waiting").chip.text, "needs you")
        XCTAssertEqual(sess("a", "waiting").chip.tone, .warning)
        XCTAssertEqual(sess("a", "running").chip.tone, .primary)
        XCTAssertEqual(sess("a", "done").chip.tone, .success)
        XCTAssertEqual(sess("a", "exited").chip.tone, .muted)
        XCTAssertEqual(sess("a", "stopped").chip.tone, .danger)
        XCTAssertEqual(sess("a", "external", source: "external").chip.text, "watching")
        XCTAssertEqual(sess("a", "weird").chip.text, "weird")
        var s = sess("a", "done"); s.cwd = ""; s.label = "Even Terminal"
        XCTAssertEqual(s.displayTitle, "Even Terminal")
        s.label = nil
        XCTAssertEqual(s.displayTitle, "Session")
    }

    func testSorted() {
        let t1 = "2026-01-01T00:00:00.000Z", t2 = "2026-01-02T00:00:00.000Z"
        let out = SessionInfo.sorted([
            sess("ext", "external", source: "external", at: t2), sess("exited", "exited", at: t2),
            sess("done", "done", at: t2), sess("runOld", "running", at: t1),
            sess("runNew", "running", at: t2), sess("wait", "waiting", at: t1),
        ])
        XCTAssertEqual(out.map(\.id), ["wait", "runNew", "runOld", "done", "exited", "ext"])
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
