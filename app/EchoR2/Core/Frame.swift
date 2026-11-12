import Foundation

struct ChatLine: Sendable, Hashable, Identifiable {
    let seq: Int
    let role: String
    let text: String
    let tool: String?
    /// Transcript line index from the hub (`i`); the dedupe key across history and live stream.
    var index: Int? = nil
    var id: String { index.map { "i\($0)" } ?? "s\(seq)" }
}

enum StreamEvent: Sendable {
    case term(Data)
    case chat(ChatLine)
    case state(String)
    case other
}

enum Frame: Sendable {
    case hello(id: String, epoch: String, seq: Int, state: String)
    case reset(epoch: String)
    case error(String)
    case event(seq: Int, StreamEvent)
    case unknown

    /// Flat all-optional shape so any hub frame decodes; never throws (D-11, D-21).
    private struct Raw: Decodable {
        var type: String?
        var kind: String?
        var id: String?
        var epoch: String?
        var seq: Int?
        var state: String?
        var code: String?
        var data: String?
        var role: String?
        var text: String?
        var tool: String?
        var i: Int?
    }

    static func decode(_ text: String) -> Frame {
        guard let r = try? JSONDecoder().decode(Raw.self, from: Data(text.utf8)) else { return .unknown }
        switch r.type {
        case "hello":
            guard let id = r.id, let epoch = r.epoch, let seq = r.seq, let state = r.state else { return .unknown }
            return .hello(id: id, epoch: epoch, seq: seq, state: state)
        case "reset":
            return r.epoch.map { .reset(epoch: $0) } ?? .unknown
        case "error":
            return .error(r.code ?? "internal")
        case nil:
            break
        default:
            return .unknown
        }
        guard let seq = r.seq, let kind = r.kind else { return .unknown }
        switch kind {
        case "term":
            guard let d = r.data.flatMap({ Data(base64Encoded: $0) }) else { return .event(seq: seq, .other) }
            return .event(seq: seq, .term(d))
        case "chat":
            guard let role = r.role, let t = r.text else { return .event(seq: seq, .other) }
            return .event(seq: seq, .chat(ChatLine(seq: seq, role: role, text: t, tool: r.tool, index: r.i)))
        case "state":
            return .event(seq: seq, r.state.map { .state($0) } ?? .other)
        default:
            return .event(seq: seq, .other)
        }
    }
}

enum ClientFrame: Sendable {
    case input(String)
    case keys(String)
    case resize(cols: Int, rows: Int)
    case interrupt

    func json() -> String {
        let o: [String: Any]
        switch self {
        case .input(let t): o = ["type": "input", "text": t]
        case .keys(let d): o = ["type": "keys", "data": d]
        case .resize(let c, let r): o = ["type": "resize", "cols": c, "rows": r]
        case .interrupt: o = ["type": "interrupt"]
        }
        let d = (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8)
        return String(decoding: d, as: UTF8.self)
    }
}
