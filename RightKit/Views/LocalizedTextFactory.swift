import SwiftUI

/// 渲染时按**当前选择的语言**解析文案。
///
/// 为什么不能直接用 `Text("中文键")`：那是走 `Bundle.main` 的进程语言，
/// 而进程语言只有启动时读一次，所以切换语言必须重启。
/// 这里显式指定 bundle，SwiftUI 每次重绘都会重新查一次，
/// 于是语言一变、界面立刻跟着变。
enum L {
    static func t(_ key: String) -> Text {
        if let bundle = LocalizedText.currentBundle {
            return Text(LocalizedStringKey(key), bundle: bundle)
        }
        // 源语言：键就是文案本身（中文），不能再查 bundle
        return Text(verbatim: key)
    }

    /// 非 View 场景（例如 NSMenuItem 的标题）用这个。
    static func s(_ key: String) -> String {
        LocalizedText.string(key, language: LocalizedText.currentLanguage)
    }
}
