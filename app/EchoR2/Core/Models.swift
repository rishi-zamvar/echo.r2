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

    enum CodingKeys: String, CodingKey {
        case ok, version, gitSha, uptime, os, hubName, epoch, claude
        case protocolVersion = "protocol"
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

    /// waiting, running/starting, done, exited/stopped/unknown, externals last.
    var sortRank: Int {
        if isExternal { return 4 }
        switch state {
        case "waiting": return 0
        case "running", "starting": return 1
        case "done": return 2
        default: return 3
        }
    }

    static func sorted(_ list: [SessionInfo]) -> [SessionInfo] {
        list.sorted {
            if $0.sortRank != $1.sortRank { return $0.sortRank < $1.sortRank }
            return ($0.startedDate ?? .distantPast) > ($1.startedDate ?? .distantPast)
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
struct PairResponse: Codable, Sendable { var token: String; var deviceId: String }
struct CreateSessionRequest: Codable, Sendable { var cwd: String; var prompt: String? }
struct CreateSessionResponse: Codable, Sendable { var id: String }
struct ErrorBody: Codable, Sendable { var error: String }
