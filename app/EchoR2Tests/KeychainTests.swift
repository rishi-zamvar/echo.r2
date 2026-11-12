import XCTest

final class KeychainTests: XCTestCase {
    func testRoundTrip() throws {
        let acct = "echor2-test-\(UUID().uuidString)"
        defer { Keychain.delete(account: acct) }
        do { try Keychain.save("one", account: acct) }
        catch let e as KeychainError where e.status == errSecInteractionNotAllowed {
            throw XCTSkip("keychain locked")
        }
        XCTAssertEqual(Keychain.load(account: acct), "one")
        try Keychain.save("two", account: acct)
        XCTAssertEqual(Keychain.load(account: acct), "two")
        Keychain.delete(account: acct)
        XCTAssertNil(Keychain.load(account: acct))
    }
}
