import Foundation
import Security

struct KeychainError: Error, Equatable { let status: OSStatus }

enum Keychain {
    static let account = "hubToken"
    private static let service = "com.rishizamvar.echor2"

    // macOS unsigned test bundles lack the keychain entitlement (-34018);
    // flip to the file-based login keychain once and remember.
    // ponytail: nonisolated(unsafe) flag, only ever flips false once
    #if os(macOS)
    nonisolated(unsafe) private static var useDataProtection = true
    #endif

    private static func base(_ account: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        if useDataProtection { q[kSecUseDataProtectionKeychain as String] = true }
        #endif
        return q
    }

    /// Runs op; on macOS retries once against the file keychain on -34018.
    private static func run(_ account: String, _ op: ([String: Any]) -> OSStatus) -> OSStatus {
        let s = op(base(account))
        #if os(macOS)
        if s == errSecMissingEntitlement && useDataProtection {
            useDataProtection = false
            return op(base(account))
        }
        #endif
        return s
    }

    static func save(_ value: String, account: String) throws {
        delete(account: account)
        let data = Data(value.utf8)
        let s = run(account) { q in
            var q = q
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(q as CFDictionary, nil)
        }
        if s != errSecSuccess { throw KeychainError(status: s) }
    }

    static func load(account: String) -> String? {
        var out: CFTypeRef?
        let s = run(account) { q in
            var q = q
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            return SecItemCopyMatching(q as CFDictionary, &out)
        }
        guard s == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let s = run(account) { SecItemDelete($0 as CFDictionary) }
        return s == errSecSuccess
    }
}
