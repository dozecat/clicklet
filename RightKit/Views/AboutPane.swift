import AppKit
import SwiftUI

/// Version, home page and licence — the things the standard About panel shows,
/// in a form that can be read without opening a panel, and with the links
/// clickable.
struct AboutPane: View {
    private let repository = URL(string: "https://github.com/dozecat/rightkit")!
    private let releases = URL(string: "https://github.com/dozecat/rightkit/releases")!

    var body: some View {
        SettingsPane {
            SettingsRow("版本") {
                SettingsValue(text: version)
            }

            SettingsRow("项目主页") {
                Button("打开 GitHub") { NSWorkspace.shared.open(repository) }
                    .help(repository.absoluteString)
            }

            SettingsRow("版本更新") {
                Button("查看 Releases") { NSWorkspace.shared.open(releases) }
                    .help("在浏览器中打开 GitHub Releases 页面")
            }

            SettingsGroupSeparator()

            SettingsRow("许可") {
                SettingsValue(text: "GNU General Public License v3.0")
            }

            SettingsRow("系统要求") {
                SettingsValue(text: "macOS 13 或更高版本")
            }

            SettingsRow("关于面板") {
                Button("打开…") { showAboutPanel() }
            }
        }
    }

    /// Marketing version plus build, which is what a bug report needs.
    private var version: String {
        let short = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    private func showAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(
            options: [
                .applicationName: "RightKit",
                .applicationVersion: version,
                .credits: NSAttributedString(
                    string: "GNU General Public License v3.0\n\(repository.absoluteString)"
                )
            ]
        )
    }
}
