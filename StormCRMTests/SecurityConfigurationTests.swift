import XCTest
@testable import StormCRM

final class SecurityConfigurationTests: XCTestCase {
    func testConfiguredAPIUsesTLS() {
        XCTAssertTrue(AppConfig.apiBaseURL.hasPrefix("https://"))
    }

    func testPIIProtectionRoundTrip() {
        let plaintext = "synthetic-security-test"
        let encrypted = PIIProtection.encrypt(plaintext)
        XCTAssertNotNil(encrypted)
        XCTAssertNotEqual(encrypted, plaintext.data(using: .utf8))
        XCTAssertEqual(encrypted.flatMap(PIIProtection.decrypt), plaintext)
    }

    func testTokensRoundTripThroughKeychain() {
        let store = TokenStore()
        store.clear()
        store.save(accessToken: "access-test", refreshToken: "refresh-test", expiresIn: 900)
        XCTAssertEqual(store.tokens?.accessToken, "access-test")
        XCTAssertEqual(store.tokens?.refreshToken, "refresh-test")
        store.clear()
        XCTAssertNil(store.tokens)
    }
}
