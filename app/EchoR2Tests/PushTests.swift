import XCTest

final class PushTests: XCTestCase {
    func testHex() {
        XCTAssertEqual(PushToken.hex(Data([0x00, 0xab, 0xff, 0x10])), "00abff10")
    }

    func testEnvDebug() {
        XCTAssertEqual(PushToken.env, "sandbox")
    }

    func testDeepLink() {
        let id = "0f8fad5b-d9cb-469f-a165-70867728950e"
        XCTAssertEqual(DeepLink.sessionId(from: ["sessionId": id, "aps": [String: Any]()]), id)
        XCTAssertEqual(DeepLink.sessionId(from: ["sessionId": id.uppercased()]), id)
        XCTAssertNil(DeepLink.sessionId(from: ["aps": [String: Any]()]))
        XCTAssertNil(DeepLink.sessionId(from: ["sessionId": 42]))
        XCTAssertNil(DeepLink.sessionId(from: ["sessionId": "../etc"]))
        XCTAssertNil(DeepLink.sessionId(from: ["sessionId": ""]))
        XCTAssertNil(DeepLink.sessionId(from: ["sessionId": String(repeating: "z", count: 36)]))
        XCTAssertEqual(DeepLink.path(opening: id), [id])
    }

    func testHealthPush() throws {
        let base = #"{"ok":true,"protocol":1,"version":"0.1.0","gitSha":"x","uptime":1,"os":"darwin","hubName":"h","epoch":"e""#
        let ready = try JSONDecoder().decode(Health.self, from: Data((base + #","push":"ready"}"#).utf8))
        XCTAssertEqual(ready.push, "ready")
        let old = try JSONDecoder().decode(Health.self, from: Data((base + "}").utf8))
        XCTAssertNil(old.push)
        XCTAssertNil(try JSONDecoder().decode(Health.self, from: fixture("health.json")).push)
    }

    func testPushTestResponse() throws {
        let j = #"{"sent":1,"results":[{"token":"abcd1234","status":200}]}"#
        let r = try JSONDecoder().decode(PushTestResponse.self, from: Data(j.utf8))
        XCTAssertEqual(r.sent, 1)
        XCTAssertEqual(r.results[0].status, 200)
        XCTAssertNil(r.results[0].reason)
    }
}
