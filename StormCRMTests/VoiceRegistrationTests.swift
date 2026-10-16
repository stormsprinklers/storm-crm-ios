import XCTest
@testable import StormCRM

@MainActor
final class VoiceRegistrationTests: XCTestCase {
    func testIncomingUsesDedicatedMobileIdentityWithoutChangingOutboundIdentity() throws {
        let response = try JSONDecoder().decode(VoiceManager.TokenResponse.self, from: Data(#"{"token":"outbound","identity":"company_user","incomingToken":"mobile-token"}"#.utf8))
        XCTAssertEqual(response.incomingRegistrationToken, "mobile-token")
        XCTAssertEqual(response.token, "outbound")
    }
    func testLegacyServerResponseStillRegistersPrimaryAccount() throws {
        let response = try JSONDecoder().decode(VoiceManager.TokenResponse.self, from: Data(#"{"token":"primary","identity":"company_user"}"#.utf8))
        XCTAssertEqual(response.incomingRegistrationToken, "primary")
    }
}
