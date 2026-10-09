import AppKit
import SwiftUI

@main
struct ClickletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Status bar icon: the Dock icon is gone (LSUIElement), so settings and the
        // self-check are reached from here.
        // The icon follows the Finder extension's state — it switches to the warning
        // style when the extension is turned off.
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
                Button {
                    showAboutPanel()
                } label: {
                    L.t("关于 Clicklet")
                }
            }

            // Remove the boilerplate menus SwiftUI generates automatically. They
            // sit in their own Commands type rather than inline: the commands
            // builder only accepts ten arguments on older SDKs, and this block
            // had grown past that, so the app no longer compiled with Xcode 16.
            RemovedMenus()

            // The self-check does not take a tab; it is reached from the Help menu —
            // only needed when something goes wrong, invisible the rest of the time.
            CommandGroup(after: .help) {
                Button {
                    OnboardingWindow.shared.show()
                } label: {
                    L.t("设置引导…")
                }
                Button {
                    SelfCheckWindow.shared.show()
                } label: {
                    L.t("检查运行状态…")
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
                .applicationName: "Clicklet",
                .credits: NSAttributedString(
                    string: "GNU General Public License v3.0\nhttps://github.com/dozecat/clicklet"
                )
            ]
        )
    }
}

/// The File, Print, Undo and Window menus SwiftUI generates are all dead in an
/// app with no documents and one fixed-size window: keeping them only makes
/// people think something is broken.
///
/// Deliberately **kept**: the App menu (About / Settings / Quit), the Edit menu's
/// Cut/Copy/Paste (needed for selectable text such as paths) and the Help menu.
/// Both ⌘Q and ⌘, live in the App menu, so removing menus must not take them out
/// along with it.
///
/// A separate `Commands` type rather than more entries in `.commands {}` keeps
/// the caller within the commands builder's ten-argument limit, which older SDKs
/// still enforce.
private struct RemovedMenus: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .importExport) {}
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .undoRedo) {}
        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .sidebar) {}
        CommandGroup(replacing: .windowSize) {}
        CommandGroup(replacing: .windowList) {}
    }
}
