@testable import CodexAudioMonitor
import XCTest

final class CodexOAuthCredentialsTests: XCTestCase {
    func testParsesOAuthCredentials() throws {
        let json = """
        {
          "OPENAI_API_KEY": null,
          "tokens": {
            "access_token": "access-token",
            "refresh_token": "refresh-token",
            "id_token": "id-token",
            "account_id": "account-123"
          },
          "last_refresh": "2025-12-20T12:34:56Z"
        }
        """

        let credentials = try CodexOAuthCredentialsStore.parse(data: Data(json.utf8))
        XCTAssertEqual(credentials.accessToken, "access-token")
        XCTAssertEqual(credentials.refreshToken, "refresh-token")
        XCTAssertEqual(credentials.idToken, "id-token")
        XCTAssertEqual(credentials.accountID, "account-123")
        XCTAssertNotNil(credentials.lastRefresh)
        XCTAssertEqual(credentials.providerLabel, "OAuth")
    }

    func testParsesAPIKeyCredentials() throws {
        let json = """
        {
          "OPENAI_API_KEY": "sk-test"
        }
        """

        let credentials = try CodexOAuthCredentialsStore.parse(data: Data(json.utf8))
        XCTAssertEqual(credentials.accessToken, "sk-test")
        XCTAssertTrue(credentials.refreshToken.isEmpty)
        XCTAssertNil(credentials.idToken)
        XCTAssertNil(credentials.accountID)
        XCTAssertEqual(credentials.providerLabel, "API key")
    }

    func testMissingTokenPayloadThrows() throws {
        let json = """
        {
          "OPENAI_API_KEY": null
        }
        """

        XCTAssertThrowsError(try CodexOAuthCredentialsStore.parse(data: Data(json.utf8))) { error in
            XCTAssertEqual(error as? CodexOAuthCredentialsError, .missingTokens)
        }
    }
}
