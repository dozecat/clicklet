import Foundation

/// Looks strings up in the language the user chose.
///
/// `String(localized:)` alone is not enough: it follows the process language, and
/// the Finder extension runs inside Finder's process, where changing that would
/// change Finder's language too. So the lproj is picked explicitly here.
enum LocalizedText {
    private static var bundles: [String: Bundle] = [:]

    /// The bundle for a language code, or nil if it is not there, in which
    /// case the caller decides how to fall back.
    private static func bundle(for code: String) -> Bundle? {
        if let cached = bundles[code] { return cached }
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        bundles[code] = bundle
        return bundle
    }

    // MARK: - Current language (queried while rendering)

    /// The app sets this from the preferences it already holds, which saves a
    /// redraw from reading the file hundreds of times. The Finder extension
    /// leaves it nil and keeps reading from disk.
    static var languageOverride: AppLanguage?

    private static var cachedLanguage: AppLanguage?
    private static var cachedAt = Date.distantPast

    /// The language in effect. Cached briefly: a single redraw asks for this
    /// hundreds of times, and reading and decoding the file each time is
    /// wasteful. Call invalidate() when the language changes.
    static var currentLanguage: AppLanguage {
        if let override = languageOverride { return override }
        if let cached = cachedLanguage, Date().timeIntervalSince(cachedAt) < 0.5 {
            return cached
        }
        let value = AppGroupStore.loadPreferences().resolvedLanguage
        cachedLanguage = value
        cachedAt = Date()
        return value
    }

    static func invalidate() {
        cachedLanguage = nil
        cachedAt = .distantPast
    }

    /// The bundle matching the current language.
    ///
    /// nil means "the key is the text". Simplified Chinese is the source
    /// language and has no zh-Hans.lproj, so it cannot be handed to bundle:
    /// nil, which would follow the process language and come out English.
    static var currentBundle: Bundle? {
        switch currentLanguage {
        case .simplifiedChinese: return nil
        case .english: return bundle(for: "en")
        }
    }

    static func string(_ key: String, language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            // The source language is the key itself: the catalog's
            // sourceLanguage is zh-Hans, so no zh-Hans.lproj is ever emitted.
            // Return the key unchanged.
            return key
        case .english:
            guard let bundle = bundle(for: "en") else {
                return String(localized: String.LocalizationValue(key))
            }
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
    }
}
