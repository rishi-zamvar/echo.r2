import Foundation

struct HistoryLine: Codable, Sendable {
    var i: Int
    var role: String
    var text: String
    var tool: String?
}

struct HistoryResponse: Codable, Sendable {
    var id: String
    var lines: [HistoryLine]
    var before: Int?
}

extension ChatLine {
    init(_ h: HistoryLine) { self.init(seq: 0, role: h.role, text: h.text, tool: h.tool, index: h.i) }

    /// Dedupes by transcript index (later copy wins), ascending by index; un-indexed lines follow in arrival order.
    static func merge(_ a: [ChatLine], _ b: [ChatLine]) -> [ChatLine] {
        var byIndex: [Int: ChatLine] = [:]
        var plain: [ChatLine] = []
        for l in a + b {
            if let i = l.index { byIndex[i] = l } else { plain.append(l) }
        }
        return byIndex.keys.sorted().compactMap { byIndex[$0] } + plain
    }
}
