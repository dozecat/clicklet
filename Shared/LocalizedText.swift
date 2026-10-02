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

    // MARK: - 当前语言（渲染时查询用）

    /// App 侧把它设成内存里的偏好，省掉一次重绘读上百次盘。
    /// 访达扩展不设它，继续按磁盘上的偏好走。
    static var languageOverride: AppLanguage?

    private static var cachedLanguage: AppLanguage?
    private static var cachedAt = Date.distantPast

    /// 当前生效的语言。带一个很短的缓存：一次界面重绘会查上百次，
    /// 每次都读盘 + 解析 JSON 太浪费。切换语言时调用 invalidate()。
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

    /// 当前语言对应的 bundle。
    ///
    /// 返回 nil 表示"键本身就是文案"——简体中文是源语言，没有 zh-Hans.lproj，
    /// 所以不能交给 bundle: nil（那会走进程语言，反而变英文）。
    static var currentBundle: Bundle? {
        switch currentLanguage {
        case .simplifiedChinese: return nil
        case .english: return bundle(for: "en")
        }
    }

    static func string(_ key: String, language: AppLanguage) -> String {
        switch language {
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
