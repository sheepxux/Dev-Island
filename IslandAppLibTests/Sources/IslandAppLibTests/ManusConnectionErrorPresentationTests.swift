import Foundation
import XCTest
@testable import IslandAppLib
import IslandCore

final class ManusConnectionErrorPresentationTests: XCTestCase {
    func testKnownErrorsUseStableActionableCopy() {
        XCTAssertEqual(
            ManusConnectionErrorPresentation.message(
                for: ManusError.unauthorized,
                language: .english
            ),
            "API key rejected by Manus. Double-check the value."
        )
        XCTAssertEqual(
            ManusConnectionErrorPresentation.message(
                for: ManusError.networkUnavailable,
                language: .english
            ),
            "Network unavailable. Check your connection and retry."
        )
        XCTAssertEqual(
            ManusConnectionErrorPresentation.message(
                for: ManusError.invalidResponse,
                language: .english
            ),
            "Manus returned an unexpected response. Try again."
        )
    }

    func testProviderAndUnknownErrorDetailsAreNeverReflected() {
        let secret = "private-task-id /Users/customer/SecretProject"
        let errors: [Error] = [
            ManusError.decodingError(underlying: SecretError(description: secret)),
            SecretError(description: secret),
        ]

        for error in errors {
            let message = ManusConnectionErrorPresentation.message(
                for: error,
                language: .english
            )
            XCTAssertFalse(message.contains(secret))
            XCTAssertFalse(message.contains("private-task-id"))
            XCTAssertFalse(message.contains("/Users/customer"))
        }
    }

    func testKnownErrorsFollowTheExplicitAppLanguage() {
        XCTAssertEqual(
            ManusConnectionErrorPresentation.message(
                for: ManusError.unauthorized,
                language: .simplifiedChinese
            ),
            "Manus 拒绝了 API 密钥，请再次检查。"
        )
        XCTAssertEqual(
            ManusConnectionErrorPresentation.message(
                for: ManusError.networkUnavailable,
                language: .simplifiedChinese
            ),
            "网络不可用，请检查连接后重试。"
        )
    }
}

private struct SecretError: Error, CustomStringConvertible {
    let description: String
}
