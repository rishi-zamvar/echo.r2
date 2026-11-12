import Foundation

enum HubError: Error, Equatable, Sendable {
    case unauthorized
    case forbidden
    case server(String, Int)
    case transport(String)

    /// nil for 2xx.
    static func map(status: Int, body: Data) -> HubError? {
        if (200..<300).contains(status) { return nil }
        if status == 401 { return .unauthorized }
        let code = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error ?? "http_\(status)"
        if status == 403 && code == "forbidden" { return .forbidden }
        return .server(code, status)
    }
}

struct HubClient: Sendable {
    let base: URL
    let token: String?

    /// "host", "host:port" -> http://host:port (default 8790). nil if invalid.
    static func baseURL(from host: String) -> URL? {
        let h = host.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty, !h.contains("://"), !h.contains("/"),
              !h.contains(where: \.isWhitespace) else { return nil }
        let parts = h.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2, let name = parts.first, !name.isEmpty else { return nil }
        var port = 8790
        if parts.count == 2 {
            guard let p = Int(parts[1]), (1...65535).contains(p) else { return nil }
            port = p
        }
        return URL(string: "http://\(name):\(port)")
    }

    func health() async throws -> Health { try await get("health") }
    func pair(code: String, deviceName: String) async throws -> PairResponse {
        try await send("pair", method: "POST", body: PairRequest(code: code, deviceName: deviceName))
    }
    func sessions() async throws -> SessionsResponse { try await get("sessions") }
    func roots() async throws -> RootsResponse { try await get("sessions/roots") }
    func createSession(cwd: String, prompt: String?) async throws -> String {
        let r: CreateSessionResponse = try await send("sessions", method: "POST",
                                                      body: CreateSessionRequest(cwd: cwd, prompt: prompt))
        return r.id
    }
    func stop(id: String) async throws {
        let _: Data = try await raw("sessions/\(id)/stop", method: "POST", body: nil)
    }
    func resume(id: String) async throws {
        let _: Data = try await raw("sessions/\(id)/resume", method: "POST", body: nil)
    }
    func takeover(id: String) async throws {
        let _: Data = try await raw("sessions/\(id)/takeover", method: "POST", body: nil)
    }
    func registerPush(token: String, env: String) async throws {
        let _: Data = try await raw("devices/push", method: "POST",
                                    body: JSONEncoder().encode(PushRegistration(token: token, env: env)))
    }
    func testPush() async throws -> PushTestResponse {
        try decode(try await raw("devices/push/test", method: "POST", body: Data("{}".utf8)))
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try decode(try await raw(path, method: "GET", body: nil))
    }
    private func send<T: Decodable, B: Encodable>(_ path: String, method: String, body: B) async throws -> T {
        try decode(try await raw(path, method: method, body: JSONEncoder().encode(body)))
    }
    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw HubError.transport("Bad response") }
    }

    private func raw(_ path: String, method: String, body: Data?) async throws -> Data {
        var req = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 10)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if let e = HubError.map(status: status, body: data) { throw e }
            return data
        } catch let e as HubError {
            throw e
        } catch {
            throw HubError.transport(error.localizedDescription)
        }
    }
}
