import XCTest

final class FrameTests: XCTestCase {
    func testHelloResetError() {
        guard case let .hello(id, epoch, seq, state) = Frame.decode(#"{"v":1,"type":"hello","id":"s1","epoch":"e1","seq":5,"state":"running"}"#) else { return XCTFail() }
        XCTAssertEqual([id, epoch, state], ["s1", "e1", "running"]); XCTAssertEqual(seq, 5)
        guard case let .reset(e) = Frame.decode(#"{"v":1,"type":"reset","epoch":"e2"}"#) else { return XCTFail() }
        XCTAssertEqual(e, "e2")
        guard case let .error(c) = Frame.decode(#"{"v":1,"type":"error","code":"read_only"}"#) else { return XCTFail() }
        XCTAssertEqual(c, "read_only")
    }

    func testTermBase64() {
        guard case let .event(seq, .term(d)) = Frame.decode(#"{"v":1,"seq":3,"kind":"term","data":"aGk="}"#) else { return XCTFail() }
        XCTAssertEqual(seq, 3); XCTAssertEqual(d, Data("hi".utf8))
    }

    func testChatAndTool() {
        guard case let .event(_, .chat(a)) = Frame.decode(#"{"v":1,"seq":4,"kind":"chat","role":"assistant","text":"yo"}"#) else { return XCTFail() }
        XCTAssertEqual(a.text, "yo"); XCTAssertNil(a.tool); XCTAssertEqual(a.id, "s4")
        guard case let .event(_, .chat(b)) = Frame.decode(#"{"v":1,"seq":5,"kind":"chat","role":"assistant","text":"x","tool":"Bash"}"#) else { return XCTFail() }
        XCTAssertEqual(b.tool, "Bash")
    }

    func testStateEvent() {
        guard case let .event(seq, .state(s)) = Frame.decode(#"{"v":1,"seq":6,"kind":"state","state":"waiting"}"#) else { return XCTFail() }
        XCTAssertEqual(seq, 6); XCTAssertEqual(s, "waiting")
    }

    func testMalformedNeverThrows() {
        for t in ["", "garbage", "[]", "{}", #"{"type":"wat"}"#, #"{"v":1,"type":"hello"}"#, #"{"seq":1}"#] {
            guard case .unknown = Frame.decode(t) else { return XCTFail(t) }
        }
        guard case let .event(2, .other) = Frame.decode(#"{"v":1,"seq":2,"kind":"future"}"#) else { return XCTFail() }
        guard case .event(3, .other) = Frame.decode(#"{"v":1,"seq":3,"kind":"chat"}"#) else { return XCTFail() }
    }

    func testClientFrames() throws {
        func obj(_ f: ClientFrame) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(f.json().utf8)) as! [String: Any]
        }
        let i = try obj(.input("hi")); XCTAssertEqual(i["type"] as? String, "input"); XCTAssertEqual(i["text"] as? String, "hi")
        let k = try obj(.keys("\u{1b}")); XCTAssertEqual(k["type"] as? String, "keys"); XCTAssertEqual(k["data"] as? String, "\u{1b}")
        let r = try obj(.resize(cols: 80, rows: 24)); XCTAssertEqual(r["cols"] as? Int, 80); XCTAssertEqual(r["rows"] as? Int, 24)
        XCTAssertEqual(try obj(.interrupt)["type"] as? String, "interrupt")
    }
}
