import Foundation

struct StreamState: Sendable, Equatable {
    var epoch: String?
    var lastSeq = 0
    /// Hub log head at the last hello; term events <= this are history (replay).
    var liveFrom = 0
}

enum Effect: Sendable {
    case resetUI
    case term(Data, replay: Bool)
    case chat(ChatLine)
    case state(String)
    case error(String)
}

/// Pure reducer: dedupes by seq, zeroes the cursor on reset BEFORE the replay (D-25).
func apply(_ f: Frame, to s: inout StreamState) -> [Effect] {
    switch f {
    case .hello(_, let epoch, let seq, let state):
        s.epoch = epoch
        s.liveFrom = seq
        return [.state(state)]
    case .reset(let epoch):
        s.epoch = epoch
        s.lastSeq = 0
        return [.resetUI]
    case .error(let code):
        return [.error(code)]
    case .unknown:
        return []
    case .event(let seq, let e):
        guard seq > s.lastSeq else { return [] }
        s.lastSeq = seq
        switch e {
        case .term(let d): return [.term(d, replay: seq <= s.liveFrom)]
        case .chat(let c): return [.chat(c)]
        case .state(let st): return [.state(st)]
        case .other: return []
        }
    }
}
