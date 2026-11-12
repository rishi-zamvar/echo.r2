import Foundation
import Observation

enum ConnectionState: Equatable {
    case unknown
    case healthy
    case unreachable(String)
}

@MainActor @Observable
final class AppModel {
    private static let hostKey = "hubHost"

    var host: String
    var token: String?
    var health: Health?
    var connectionState: ConnectionState = .unknown
    var lastSuccessfulCall: Date?
    var demoMode = false
    var sessions: [SessionInfo] = []
    var sessionsLoaded = false
    /// NavigationStack path: session ids.
    var path: [String] = []
    var pushAuthorized: Bool?
    var pushRegistered = false
    var pushError: String?

    var isPaired: Bool { token != nil }

    init() {
        host = UserDefaults.standard.string(forKey: Self.hostKey) ?? "rishis-macbook-pro.tail748eb9.ts.net:8790"
        token = Keychain.load(account: Keychain.account)
    }

    func client() -> HubClient? {
        HubClient.baseURL(from: host).map { HubClient(base: $0, token: token) }
    }

    /// Unauthenticated /health probe for the pairing screen.
    func checkHealth(host: String) async -> Result<Health, HubError> {
        guard let base = HubClient.baseURL(from: host) else { return .failure(.transport("Invalid host")) }
        do { return .success(try await HubClient(base: base, token: nil).health()) }
        catch let e as HubError { return .failure(e) }
        catch { return .failure(.transport(error.localizedDescription)) }
    }

    /// deviceName is passed in by the view so Core stays UIKit-free.
    func pair(host: String, code: String, deviceName: String) async throws {
        guard let base = HubClient.baseURL(from: host) else { throw HubError.transport("Invalid host") }
        let r = try await HubClient(base: base, token: nil).pair(code: code.uppercased(), deviceName: deviceName)
        try Keychain.save(r.token, account: Keychain.account)
        UserDefaults.standard.set(host.trimmingCharacters(in: .whitespaces), forKey: Self.hostKey)
        self.host = host.trimmingCharacters(in: .whitespaces)
        token = r.token
        markOK()
    }

    func forget() {
        Keychain.delete(account: Keychain.account)
        UserDefaults.standard.removeObject(forKey: Self.hostKey)
        token = nil
        health = nil
        sessions = []
        sessionsLoaded = false
        path = []
        pushRegistered = false
        pushError = nil
        connectionState = .unknown
    }

    func registerPush(token: String) async {
        guard let c = client() else { return }
        do {
            try await c.registerPush(token: token, env: PushToken.env)
            pushRegistered = true
            pushError = nil
        } catch {
            pushError = "Push registration failed"
            if case .unauthorized? = error as? HubError { handle(error) }
        }
    }

    /// Deep link from a tapped push; opens even if the list has not caught up.
    func open(sessionId: String) async {
        guard isPaired else { return }
        if !sessions.contains(where: { $0.id == sessionId }) { await refreshSessions() }
        path = DeepLink.path(opening: sessionId)
    }

    func handle(_ error: Error) {
        switch error as? HubError {
        case .unauthorized: forget()
        case .forbidden: connectionState = .unreachable("Hub refused this device")
        default: connectionState = .unreachable("Hub unreachable")
        }
    }

    func markOK() {
        connectionState = .healthy
        lastSuccessfulCall = Date()
    }

    func bootstrap() async {
        guard let c = client() else { return }
        do { health = try await c.health(); markOK() }
        catch { handle(error); return }
        await refreshSessions()
    }

    /// On failure the last-known list stays in place.
    func refreshSessions() async {
        guard let c = client() else { return }
        do {
            sessions = SessionInfo.sorted(try await c.sessions().sessions)
            sessionsLoaded = true
            markOK()
        } catch { handle(error) }
    }

    func pollSessions() async {
        while !Task.isCancelled {
            await refreshSessions()
            try? await Task.sleep(for: .seconds(3))
        }
    }
}
