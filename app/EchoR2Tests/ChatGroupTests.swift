import XCTest

final class ChatGroupTests: XCTestCase {
    private func l(_ i: Int, _ role: String, tool: String? = nil) -> ChatLine {
        ChatLine(seq: 0, role: role, text: "t\(i)", tool: tool, index: i)
    }

    func testConsecutiveToolsCollapse() {
        let lines = [l(0, "user"), l(1, "assistant"), l(2, "assistant", tool: "Bash"),
                     l(3, "assistant", tool: "Read"), l(4, "assistant", tool: "Edit"), l(5, "assistant")]
        let g = ChatGroup.group(lines)
        XCTAssertEqual(g, [.message(lines[0]), .message(lines[1]),
                           .tools(id: lines[2].id, Array(lines[2...4])), .message(lines[5])])
    }

    func testSingleToolIsAGroup() {
        let t = l(0, "assistant", tool: "Bash")
        XCTAssertEqual(ChatGroup.group([t]), [.tools(id: t.id, [t])])
    }

    func testGroupIdStableAcrossAppends() {
        let a = [l(0, "user"), l(1, "assistant", tool: "Bash")]
        let b = a + [l(2, "assistant", tool: "Read"), l(3, "assistant")]
        XCTAssertEqual(ChatGroup.group(a).map(\.id), ["i0", "i1"])
        XCTAssertEqual(ChatGroup.group(b).map(\.id), ["i0", "i1", "i3"])
    }
}
