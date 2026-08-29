import Foundation
import IslandCore

/// Fixed, actionable connection copy for the Manus setup surface.
///
/// Error descriptions can contain response details, paths, URLs, or provider
/// text. They must never be reflected into the UI; diagnostics stay
/// category-based and the user always gets bounded product copy.
enum ManusConnectionErrorPresentation {
    static func message(
        for error: Error,
        language: DevIslandLanguage = .current
    ) -> String {
        let key: String
        guard let manusError = error as? ManusError else {
            return L10n.string(
                "Couldn't connect to Manus. Try again.",
                language: language
            )
        }

        switch manusError {
        case .unauthorized:
            key = "API key rejected by Manus. Double-check the value."
        case .networkUnavailable:
            key = "Network unavailable. Check your connection and retry."
        case .rateLimited:
            key = "Manus is temporarily rate-limiting requests. Try again shortly."
        case .invalidURL:
            key = "Couldn't create a secure Manus request. Try again."
        case .invalidResponse, .decodingError:
            key = "Manus returned an unexpected response. Try again."
        case .httpError:
            key = "Manus is temporarily unavailable. Try again shortly."
        }
        return L10n.string(key, language: language)
    }
}
