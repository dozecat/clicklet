import AppKit
import SwiftUI

@main
struct RightKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 状态栏图标：Dock 图标没了（LSUIElement），设置与自检从这里进。
        // 图标会跟着访达扩展的状态变——扩展被关掉时换成警示样式。
        MenuBarExtra {
            StatusItemMenu()
        } label: {
            StatusItemLabel()
        }
        .menuBarExtraStyle(.menu)

        // A Settings scene, not a Window: macOS creates it only when the user
        // asks for it. A Window scene opens at launch, so every Finder action
        // that woke the app showed this window for a frame before the action
        // hid the app again — the flash.
        //
        // URLs arrive through `AppDelegate.application(_:open:)`, which does not
        // need a window to exist.
        Settings {
            SettingsWindowView()
        }
        // A small fixed window with the tab strip acting as the title bar, the
        // way Safari's settings window is built.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 RightKit") {
                    showAboutPanel()
                }
            }

            // 删掉 SwiftUI 自动生成的样板菜单。
            //
            // 这个 App 没有文档概念、只有一个固定尺寸的设置窗口，所以「文件」
            // 「显示」「窗口缩放」里的条目全是死的——留着只会让人以为是坏的。
            //
            // 刻意**保留**的：App 菜单（关于 / 设置 / 退出）、编辑菜单的剪切
            // 拷贝粘贴（路径那类可选文本要用）、帮助菜单。⌘Q 与 ⌘, 都在 App
            // 菜单里，删菜单时不能把它们一起删掉。
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .importExport) {}
            CommandGroup(replacing: .printItem) {}
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .windowSize) {}
            CommandGroup(replacing: .windowList) {}

            // 自检不占页签，从「帮助」菜单进——出问题时才需要，平时不可见。
            CommandGroup(after: .help) {
                Button("检查运行状态…") {
                    SettingsStore.shared.showHealthCheck()
                    SettingsOpener.show()
                }
            }

            // Replaced on purpose this time: `SettingsLink` is the only route
            // SwiftUI supports for the Settings scene on macOS 14 and later.
            CommandGroup(replacing: .appSettings) {
                SettingsMenuButton()
            }

        }
    }

    private func showAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(
            options: [
                .applicationName: "RightKit",
                .credits: NSAttributedString(
                    string: "GNU General Public License v3.0\nhttps://github.com/dozecat/rightkit"
                )
            ]
        )
    }

}
