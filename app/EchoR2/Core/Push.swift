import Foundation

enum PushToken {
    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    #if DEBUG
    static var env: String { "sandbox" }
    #else
    static var env: String { "production" }
    #endif
}

enum DeepLink {
    /// Only uuid-shaped strings are accepted (T-04-18); returned lowercased.
    static func sessionId(from userInfo: [AnyHashable: Any]) -> String? {
        guard let s = userInfo["sessionId"] as? String,
              s.range(of: "^[0-9a-f-]{36}$", options: [.regularExpression, .caseInsensitive]) != nil
        else { return nil }
        return s.lowercased()
    }

    static func path(opening id: String) -> [String] { [id] }
}
