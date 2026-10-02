import Foundation

/// 按**用户选的语言**查文案。
///
/// 不能只用 `String(localized:)`：它走进程语言，而访达扩展跑在 Finder 进程里，
/// 改进程语言等于改访达的语言。所以这里显式挑 lproj。
enum LocalizedText {
    private static var bundles: [String: Bundle] = [:]

    /// 取指定语言的 bundle。找不到就返回 nil，由调用方决定回退。
    private static func bundle(for code: String) -> Bundle? {
        if let cached = bundles[code] { return cached }
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        bundles[code] = bundle
        return bundle
    }

    static func string(_ key: String, language: AppLanguage) -> String {
        switch language {
        case .system:
            // 跟随系统：交给进程语言
            return String(localized: String.LocalizationValue(key))
        case .simplifiedChinese:
            // 源语言就是键本身（catalog 的 sourceLanguage 是 zh-Hans，
            // 所以**不会**有 zh-Hans.lproj 可查），直接返回键
            return key
        case .english:
            guard let bundle = bundle(for: "en") else {
                return String(localized: String.LocalizationValue(key))
            }
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
    }
}
