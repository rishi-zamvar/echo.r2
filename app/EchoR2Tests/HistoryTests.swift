import XCTest

final class HistoryTests: XCTestCase {
    func testResponseDecodes() throws {
        let r = try JSONDecoder().decode(HistoryResponse.self, from: Data(
            #"{"id":"s1","lines":[{"i":0,"role":"user","text":"hi"},{"i":1,"role":"assistant","text":"x","tool":"Bash"}],"before":null}"#.utf8))
        XCTAssertEqual(r.id, "s1"); XCTAssertEqual(r.lines.count, 2)
        XCTAssertEqual(r.lines[1].tool, "Bash"); XCTAssertNil(r.before)
    }

    func testFrameCarriesIndex() {
        guard case let .event(_, .chat(a)) = Frame.decode(#"{"v":1,"seq":3,"kind":"chat","role":"user","text":"a","i":7}"#) else { return XCTFail() }
        XCTAssertEqual(a.index, 7); XCTAssertEqual(a.id, "i7")
        guard case let .event(_, .chat(b)) = Frame.decode(#"{"v":1,"seq":4,"kind":"chat","role":"user","text":"b"}"#) else { return XCTFail() }
        XCTAssertNil(b.index)
    }

    private func l(_ i: Int?, _ t: String = "x") -> ChatLine { ChatLine(seq: 0, role: "user", text: t, tool: nil, index: i) }

    func testMergeDedupesAndOrders() {
        let m = ChatLine.merge([l(5), l(6)], [l(6, "new"), l(7)])
        XCTAssertEqual(m.map(\.index), [5, 6, 7])
        XCTAssertEqual(m[1].text, "new")
    }

    func testPrependOlderPageKeepsAscending() {
        let m = ChatLine.merge([l(5), l(6)], [l(3), l(4)])
        XCTAssertEqual(m.map(\.index), [3, 4, 5, 6])
    }

    func testUnindexedAppendInArrivalOrder() {
        let m = ChatLine.merge([l(1), l(nil, "a")], [l(nil, "b"), l(0)])
        XCTAssertEqual(m.map(\.text), ["x", "x", "a", "b"])
        XCTAssertEqual(m.compactMap(\.index), [0, 1])
    }
}
