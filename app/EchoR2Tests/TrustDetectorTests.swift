import XCTest

final class TrustDetectorTests: XCTestCase {
    private func d(_ s: String) -> Data { Data(s.utf8) }

    func testPlainPhrase() {
        var t = TrustDetector()
        XCTAssertTrue(t.feed(d("Do you trust the files in this folder?")))
    }

    func testSplitAcrossChunks() {
        var t = TrustDetector()
        XCTAssertFalse(t.feed(d("Do you tr")))
        XCTAssertTrue(t.feed(d("ust the files in this folder")))
    }

    func testAnsiAndOscStripped() {
        var t = TrustDetector()
        XCTAssertTrue(t.feed(d("\u{1b}]0;title\u{07}\u{1b}[1mDo you\u{1b}[0m trust the files in this folder")))
    }

    func testVariantAndCase() {
        var t = TrustDetector()
        XCTAssertTrue(t.feed(d("Trust This Folder?")))
    }

    func testUnrelatedAndTailBound() {
        var t = TrustDetector()
        XCTAssertFalse(t.feed(d(String(repeating: "hello ", count: 1000))))
        XCTAssertLessThanOrEqual(t.tail.count, 2048)
    }

    func testResetClearsTail() {
        var t = TrustDetector()
        XCTAssertTrue(t.feed(d("trust this folder")))
        t.reset()
        XCTAssertFalse(t.feed(d("unrelated")))
    }
}
