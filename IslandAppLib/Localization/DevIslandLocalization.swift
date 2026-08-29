import Foundation
import SwiftUI

/// The product supports a deliberately small, explicit language set. Keeping
/// this independent from `AppleLanguages` lets Dev Island change its own UI
/// without mutating a system-wide preference or requiring a relaunch.
public enum DevIslandLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public static let preferenceKey = "devIsland.interfaceLanguage"

    public var id: String { rawValue }

    public static var current: DevIslandLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: preferenceKey),
              let language = DevIslandLanguage(rawValue: rawValue) else {
            return .system
        }
        return language
    }

    public var resolvedIdentifier: String {
        switch self {
        case .system:
            return Self.supportedIdentifier(for: Locale.preferredLanguages)
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }

    public var locale: Locale {
        Locale(identifier: resolvedIdentifier)
    }

    public var displayKey: String {
        switch self {
        case .system:            return "System Default"
        case .english:           return "English"
        case .simplifiedChinese: return "Simplified Chinese"
        }
    }

    /// Maps the system language list to the translations actually shipped by
    /// Dev Island. Traditional Chinese deliberately falls back to English
    /// until a reviewed `zh-Hant` translation exists.
    public static func supportedIdentifier(for preferredLanguages: [String]) -> String {
        guard let preferred = preferredLanguages.first else { return "en" }
        let normalized = preferred.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized == "zh"
            || normalized.hasPrefix("zh-hans")
            || normalized.hasPrefix("zh-cn")
            || normalized.hasPrefix("zh-sg") {
            return "zh-Hans"
        }
        return "en"
    }
}

/// Localizes strings that must exist as `String` values (model labels,
/// accessibility summaries and AppKit copy). Literal SwiftUI labels continue
/// to use the normal localized-key path from the app's main bundle.
public enum L10n {
    public static func string(
        _ key: String,
        language: DevIslandLanguage = .current
    ) -> String {
        let identifier = language.resolvedIdentifier

        // Packaged apps receive the lproj directories in Contents/Resources.
        // Prefer that location so the executable never depends on SwiftPM's
        // development-only resource-bundle path.
        if let bundle = languageBundle(in: .main, identifier: identifier) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }

        #if SWIFT_PACKAGE
        // Unit tests and `swift run` use the target resource bundle.
        if let bundle = languageBundle(in: .module, identifier: identifier) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
        #endif

        return key
    }

    public static func format(
        _ key: String,
        language: DevIslandLanguage = .current,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: string(key, language: language),
            locale: language.locale,
            arguments: arguments
        )
    }

    public static func sessionCount(
        _ count: Int,
        language: DevIslandLanguage = .current
    ) -> String {
        format(
            count == 1 ? "%lld session" : "%lld sessions",
            language: language,
            Int64(count)
        )
    }

    public static func agentConnectionSummary(
        connected: Int,
        updateRequired: Int,
        configured: Int,
        language: DevIslandLanguage = .current
    ) -> String {
        if updateRequired > 0 {
            return format(
                updateRequired == 1 ? "%lld update" : "%lld updates",
                language: language,
                Int64(updateRequired)
            )
        }

        if configured > 0 {
            let reviewCount = format(
                configured == 1 ? "%lld check" : "%lld checks",
                language: language,
                Int64(configured)
            )
            return format(
                "%lld connected · %@",
                language: language,
                Int64(connected),
                reviewCount
            )
        }

        return format(
            "%lld connected",
            language: language,
            Int64(connected)
        )
    }

    private static func languageBundle(in bundle: Bundle, identifier: String) -> Bundle? {
        let candidates = identifier == "zh-Hans"
            // SwiftPM canonicalizes this resource directory to lower-case
            // `zh-hans.lproj`; packaged app resources preserve `zh-Hans`.
            ? ["zh-Hans", "zh-hans", "zh_CN", "zh"]
            : [identifier, "en"]

        for candidate in candidates {
            if let path = bundle.path(forResource: candidate, ofType: "lproj"),
               let languageBundle = Bundle(path: path) {
                return languageBundle
            }
        }
        return nil
    }
}

private struct DevIslandLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue = DevIslandLanguage.current
}

public extension EnvironmentValues {
    var devIslandLanguage: DevIslandLanguage {
        get { self[DevIslandLanguageEnvironmentKey.self] }
        set { self[DevIslandLanguageEnvironmentKey.self] = newValue }
    }
}

/// Reactive localization boundary used by every AppKit-hosted SwiftUI root.
/// Changing the setting refreshes all open Dev Island windows in place.
public struct LocalizedAppRoot<Content: View>: View {
    @AppStorage(DevIslandLanguage.preferenceKey)
    private var storedLanguage = DevIslandLanguage.system.rawValue

    private let overrideLanguage: DevIslandLanguage?
    private let content: Content

    public init(
        language: DevIslandLanguage? = nil,
        @ViewBuilder content: () -> Content
    ) {
        overrideLanguage = language
        self.content = content()
    }

    public var body: some View {
        let language = overrideLanguage
            ?? DevIslandLanguage(rawValue: storedLanguage)
            ?? .system

        content
            .environment(\.devIslandLanguage, language)
            .environment(\.locale, language.locale)
    }
}
