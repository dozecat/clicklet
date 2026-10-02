import SwiftUI

/// Resolves strings against the language the user picked, at render time.
///
/// `Text("key")` alone follows the process language of Bundle.main, which is
/// read once at startup, so switching language would need a relaunch. Passing
/// the bundle explicitly makes SwiftUI look the string up again on every
/// redraw, so the interface follows the pick immediately.
enum L {
    static func t(_ key: String) -> Text {
        if let bundle = LocalizedText.currentBundle {
            return Text(LocalizedStringKey(key), bundle: bundle)
        }
        // Source language: the key is the text, so there is no bundle to consult.
        return Text(verbatim: key)
    }

    /// For places that are not views, such as an NSMenuItem title.
    static func s(_ key: String) -> String {
        LocalizedText.string(key, language: LocalizedText.currentLanguage)
    }
}
