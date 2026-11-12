import Foundation

/// Detects Claude's folder-trust dialog in live terminal output (D-18).
/// Keeps a rolling 2048-char tail of ANSI-stripped, lowercased text so phrases split across chunks still match.
struct TrustDetector: Sendable {
    private(set) var tail = ""

    private static let phrases = ["do you trust the files in this folder", "trust this folder"]

    mutating func feed(_ data: Data) -> Bool {
        let text = Self.strip(String(decoding: data, as: UTF8.self)).lowercased()
        tail = String((tail + text).suffix(2048))
        return Self.phrases.contains { tail.contains($0) }
    }

    /// Drops CSI (ESC [ ... final @-~) and OSC (ESC ] ... BEL | ESC \\) sequences.
    private static func strip(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var it = s.unicodeScalars.makeIterator()
        while let c = it.next() {
            guard c == "\u{1b}" else { out.append(c); continue }
            switch it.next() {
            case "[": while let f = it.next(), !("@"..."~").contains(f) {}
            case "]":
                while let f = it.next() {
                    if f == "\u{07}" { break }
                    if f == "\u{1b}" { _ = it.next(); break }
                }
            default: break
            }
        }
        return String(out)
    }

    mutating func reset() { tail = "" }
}
