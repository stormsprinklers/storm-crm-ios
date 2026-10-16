import XCTest
@testable import StormCRM

@MainActor
final class VoiceRegistrationTests: XCTestCase {
    func testRegistersEveryLinkedCompanyRatherThanOnlySelectedCompany() throws {
        let response = try JSONDecoder().decode(VoiceManager.TokenResponse.self, from: Data(#"{"token":"selected","identity":"storm_user","identities":[{"token":"storm-token","identity":"storm_user"},{"token":"chestnut-token","identity":"chestnut_user"}]}"#.utf8))
        XCTAssertEqual(response.incomingTokens, ["storm-token", "chestnut-token"])
    }

    func testLegacyAndEmptyIdentityResponsesStillRegisterPrimaryAccount() throws {
        for payload in [#"{"token":"primary","identity":"company_user"}"#, #"{"token":"primary","identity":"company_user","identities":[]}"#] {
            let response = try JSONDecoder().decode(VoiceManager.TokenResponse.self, from: Data(payload.utf8))
            XCTAssertEqual(response.incomingTokens, ["primary"])
        }
    }
}
