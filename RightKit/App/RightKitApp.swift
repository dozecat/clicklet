import AppKit
import SwiftUI

@main
struct RightKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("RightKit 设置", id: "rightkit-main") {
            SettingsWindowView()
                .onOpenURL { url in
                    ActionCoordinator.shared.handle(url: url)
                }
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

            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
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

    /// Brings the single settings window forward; the app has no other window,
    /// so the first main-capable one is it.
    private func showSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
}
