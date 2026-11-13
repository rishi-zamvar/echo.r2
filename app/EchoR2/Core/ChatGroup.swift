/// A chat row: one message bubble, or a run of consecutive tool lines shown as "Used N tools".
enum ChatItem: Identifiable, Hashable, Sendable {
    case message(ChatLine)
    /// `id` is the first tool line's id, so appending to the run keeps the row identity.
    case tools(id: String, [ChatLine])

    var id: String {
        switch self {
        case .message(let l): l.id
        case .tools(let id, _): id
        }
    }
}

enum ChatGroup {
    static func group(_ lines: [ChatLine]) -> [ChatItem] {
        var out: [ChatItem] = []
        for l in lines {
            if l.tool != nil {
                if case .tools(let id, let run)? = out.last {
                    out[out.count - 1] = .tools(id: id, run + [l])
                } else {
                    out.append(.tools(id: l.id, [l]))
                }
            } else {
                out.append(.message(l))
            }
        }
        return out
    }
}
