import Foundation
import Observation

enum AutoPairOutcome: Equatable {
    case paired
    case refused(String)
    case unreachable
}

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
    /// One auto-pair attempt per launch / per forget() so a refusal never loops (T-05-24).
    var autoPairTried = false

    var isPaired: Bool { token != nil }

    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTestReset") {
            Keychain.delete(account: Keychain.account)
            UserDefaults.standard.removeObject(forKey: Self.hostKey)
        }
        func arg(_ name: String) -> String? { args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        let testHost = arg("-uiTestHubHost"), testToken = arg("-uiTestToken")
        #else
        let testHost: String? = nil, testToken: String? = nil
        #endif
        host = testHost ?? UserDefaults.standard.string(forKey: Self.hostKey) ?? "rishis-macbook-pro.tail748eb9.ts.net:8790"
        token = testToken ?? Keychain.load(account: Keychain.account)
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
        // Unsigned simulator test builds have no keychain entitlement; keep the token in memory so this session works.
        try? Keychain.save(r.token, account: Keychain.account)
        UserDefaults.standard.set(host.trimmingCharacters(in: .whitespaces), forKey: Self.hostKey)
        self.host = host.trimmingCharacters(in: .whitespaces)
        token = r.token
        markOK()
    }

    func autoPair(deviceName: String) async -> AutoPairOutcome {
        autoPairTried = true
        guard let c = client() else { return .unreachable }
        do {
            let r = try await HubClient(base: c.base, token: nil).pairAuto(deviceName: deviceName)
            // Unsigned simulator test builds have no keychain entitlement; keep the token in memory so this session works.
        try? Keychain.save(r.token, account: Keychain.account)
            UserDefaults.standard.set(host.trimmingCharacters(in: .whitespaces), forKey: Self.hostKey)
            token = r.token
            markOK()
            Haptics.paired()
            return .paired
        } catch HubError.server(let code, _) {
            return .refused(code)
        } catch HubError.forbidden {
            return .refused("forbidden")
        } catch {
            return .unreachable
        }
    }

    func forget() {
        autoPairTried = false
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

    @ObservationIgnored private var reconnectTask: Task<Void, Never>?

    /// A stream is reconnecting; only surface "unreachable" if it is still down after 3 s (D-04).
    func relayReconnecting() {
        guard reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            self.connectionState = .unreachable("Reconnecting")
        }
    }

    func markOK() {
        reconnectTask?.cancel(); reconnectTask = nil
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
