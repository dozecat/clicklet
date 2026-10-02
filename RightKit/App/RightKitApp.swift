import AppKit
import SwiftUI

@main
struct RightKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
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
