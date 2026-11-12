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
        return (cwd as NSString).lastPathComponent
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
