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

    var isPaired: Bool { token != nil }

    init() {
        host = UserDefaults.standard.string(forKey: Self.hostKey) ?? "rishis-macbook-pro:8790"
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
        connectionState = .unknown
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
        catch { handle(error) }
    }
}
