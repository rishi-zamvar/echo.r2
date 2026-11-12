import Foundation

struct ClaudeInfo: Codable, Hashable, Sendable {
    var ok: Bool
    var version: String?
}

struct Health: Codable, Hashable, Sendable {
    var ok: Bool
    var protocolVersion: Int
    var version: String
    var gitSha: String
    var uptime: Double
    var os: String
    var hubName: String
    var epoch: String
    var claude: ClaudeInfo?
    /// "unconfigured" | "ready"; absent on older hubs.
    var push: String?
    var pushLastError: PushError?

    enum CodingKeys: String, CodingKey {
        case ok, version, gitSha, uptime, os, hubName, epoch, claude, push, pushLastError
        case protocolVersion = "protocol"
    }
}

struct PushError: Codable, Hashable, Sendable {
    var status: Int
    var reason: String?
    var message: String
    var at: String
}

enum PairingCode {
    /// Strip non-alphanumerics, uppercase, then cap at 8.
    static func normalize(_ s: String) -> String {
        String(s.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.uppercased().prefix(8))
    }
}

enum ChipTone: Sendable { case primary, warning, success, muted, danger, accent }

struct SessionInfo: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var cwd: String
    var pid: Int?
    var state: String
    var source: String
    var startedAt: String?
    var label: String?
    var title: String?
    var summary: String?
    var noise: Bool?
    var lastActivity: String?
    var entrypoint: String?

    private static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
    var lastActivityDate: Date? { Self.parse(lastActivity) }
    var startedDate: Date? {
        guard let startedAt else { return nil }
        return try? Date(startedAt, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
    var isExternal: Bool { source == "external" }
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if !cwd.isEmpty { return (cwd as NSString).lastPathComponent }
        if let label, !label.isEmpty { return label }
        return "Session"
    }

    var chip: (text: String, tone: ChipTone) {
        if isExternal { return ("watching", .accent) }
        switch state {
        case "running", "starting": return (state, .primary)
        case "waiting": return ("needs you", .warning)
        case "done": return ("done", .success)
        case "stopped": return ("stopped", .danger)
        default: return (state, .muted)
        }
    }

    enum Activity: Sendable { case running, needsYou, idle }
    var activity: Activity {
        if isExternal { return .idle }
        switch state {
        case "running", "starting": return .running
        case "waiting": return .needsYou
        default: return .idle
        }
    }

    /// D-08: waiting, then running, then everything else; each by last activity desc.
    private var sortRank: Int { activity == .needsYou ? 0 : activity == .running ? 1 : 2 }

    static func sorted(_ list: [SessionInfo]) -> [SessionInfo] {
        func t(_ s: SessionInfo) -> Date { s.lastActivityDate ?? s.startedDate ?? .distantPast }
        return list.sorted {
            if $0.sortRank != $1.sortRank { return $0.sortRank < $1.sortRank }
            return t($0) > t($1)
        }
    }
}

struct SessionsResponse: Codable, Hashable, Sendable {
    var epoch: String
    var sessions: [SessionInfo]
}

struct Root: Codable, Hashable, Sendable {
    var root: String
    var dirs: [String]
    /// The root itself plus each child dir, as absolute paths.
    var cwdOptions: [String] { [root] + dirs.map { root + "/" + $0 } }
}

struct RootsResponse: Codable, Hashable, Sendable {
    var roots: [Root]
}

struct PairRequest: Codable, Sendable { var code: String; var deviceName: String }
struct PairAutoRequest: Codable, Sendable { var deviceName: String }
struct PairResponse: Codable, Sendable { var token: String; var deviceId: String }
struct CreateSessionRequest: Codable, Sendable { var cwd: String; var prompt: String? }
struct CreateSessionResponse: Codable, Sendable { var id: String }
struct PushRegistration: Codable, Sendable { var token: String; var env: String }
struct PushResult: Codable, Hashable, Sendable { var token: String; var status: Int; var reason: String?; var message: String? }
struct PushTestResponse: Codable, Hashable, Sendable { var sent: Int; var results: [PushResult] }
struct ErrorBody: Codable, Sendable { var error: String }
