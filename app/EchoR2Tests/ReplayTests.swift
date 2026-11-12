import XCTest

final class ReplayTests: XCTestCase {
    private func chat(_ seq: Int) -> Frame { .event(seq: seq, .chat(ChatLine(seq: seq, role: "user", text: "m\(seq)", tool: nil))) }
    private func term(_ seq: Int) -> Frame { .event(seq: seq, .term(Data([UInt8(seq)]))) }

    func testDuplicatesDropped() {
        var s = StreamState()
        XCTAssertEqual(apply(chat(1), to: &s).count, 1)
        XCTAssertTrue(apply(chat(1), to: &s).isEmpty)
        XCTAssertEqual(s.lastSeq, 1)
        XCTAssertEqual(apply(chat(2), to: &s).count, 1)
        XCTAssertEqual(s.lastSeq, 2)
    }

    func testHelloSetsEpochAndLiveFromNotLastSeq() {
        var s = StreamState(epoch: nil, lastSeq: 3, liveFrom: 0)
        let fx = apply(.hello(id: "a", epoch: "e", seq: 9, state: "running"), to: &s)
        XCTAssertEqual(s.epoch, "e"); XCTAssertEqual(s.liveFrom, 9); XCTAssertEqual(s.lastSeq, 3)
        guard case .state("running") = fx.first else { return XCTFail() }
    }

    func testReplayFlagOnTerm() {
        var s = StreamState()
        _ = apply(.hello(id: "a", epoch: "e", seq: 2, state: "running"), to: &s)
        guard case .term(_, replay: true) = apply(term(2), to: &s).first else { return XCTFail() }
        guard case .term(_, replay: false) = apply(term(3), to: &s).first else { return XCTFail() }
    }

    func testResetZeroesLastSeqBeforeReplay() {
        var s = StreamState(epoch: "old", lastSeq: 50, liveFrom: 50)
        guard case .resetUI = apply(.reset(epoch: "new"), to: &s).first else { return XCTFail() }
        XCTAssertEqual(s.lastSeq, 0); XCTAssertEqual(s.epoch, "new")
        for i in 1...3 { XCTAssertEqual(apply(chat(i), to: &s).count, 1) }
        XCTAssertEqual(s.lastSeq, 3)
    }

    func testUnknownKindAdvancesSilently() {
        var s = StreamState()
        XCTAssertTrue(apply(.event(seq: 4, .other), to: &s).isEmpty)
        XCTAssertEqual(s.lastSeq, 4)
        XCTAssertTrue(apply(.unknown, to: &s).isEmpty)
    }

    func testErrorFrame() {
        var s = StreamState()
        guard case .error("not_running") = apply(.error("not_running"), to: &s).first else { return XCTFail() }
    }

    func testOrdinaryReconnectNeverResetsUI() {
        var s = StreamState(epoch: "e", lastSeq: 2, liveFrom: 0)
        let fx = apply(.hello(id: "a", epoch: "e", seq: 2, state: "idle"), to: &s)
        XCTAssertFalse(fx.contains { if case .resetUI = $0 { true } else { false } })
    }

    func testReconnectSeededCursorAppliesOnlyNewEvents() {
        var a = StreamState()
        _ = apply(.hello(id: "s", epoch: "e", seq: 5, state: "running"), to: &a)
        for i in 1...5 { _ = apply(chat(i), to: &a) }
        XCTAssertEqual(a, StreamState(epoch: "e", lastSeq: 5, liveFrom: 5))

        var b = StreamState(epoch: a.epoch, lastSeq: a.lastSeq)
        var lines: [ChatLine] = []
        var frames: [Frame] = [.hello(id: "s", epoch: "e", seq: 7, state: "running")]
        frames += (1...7).map(chat)
        for f in frames {
            for case .chat(let l) in apply(f, to: &b) { lines.append(l) }
        }
        XCTAssertEqual(lines.map(\.seq), [6, 7])
        XCTAssertEqual(b.lastSeq, 7)
    }
}
