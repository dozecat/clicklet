import AppKit
import SwiftUI

/// Opens the settings window from outside SwiftUI's view tree — the Dock icon,
/// for instance.
///
/// macOS 14 dropped the `showSettingsWindow:` selector, and SwiftUI answers only
/// through `SettingsLink` / the `openSettings` environment action, both of which
/// are views. So the settings view hands its action back here, and this prefers
/// it over the legacy selectors.
///
/// Every attempt is logged: which route did or did not work is otherwise
/// invisible, and this has gone wrong twice already.
@MainActor
enum SettingsOpener {
    /// Captured from the settings view with `@Environment(\.openSettings)`.
    private static var openSettings: (() -> Void)?

    static func adopt(_ action: @escaping () -> Void) {
        openSettings = action
    }

    static func show() {
        NSApp.activate(ignoringOtherApps: true)

        if let openSettings {
            DiagnosticsLog.log("settings: opening via openSettings")
            openSettings()
            return
        }

        // Performing the app menu's own item. SwiftUI's `SettingsLink` installs
        // a `menuAction:` there, and that is a route which works.
        //
        // The old `showSettingsWindow:` selector is deliberately NOT used: on
        // macOS 14+ it answers `true` while doing nothing at all, so it looks
        // like success and silently drops the request. A probe confirmed this.
        if performAppMenuSettingsItem() {
            DiagnosticsLog.log("settings: opened via the app menu item")
            return
        }

        if let window = NSApp.windows.first(where: \.canBecomeMain) {
            DiagnosticsLog.log("settings: bringing an existing window forward")
            window.makeKeyAndOrderFront(nil)
            return
        }

        DiagnosticsLog.log(
            "settings: no route worked; windows=\(NSApp.windows.count)"
        )
    }

    /// Performs the app menu's settings item, found by its ⌘, shortcut or its
    /// title so that it does not depend on the interface language.
    private static func performAppMenuSettingsItem() -> Bool {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else {
            return false
        }

        let index = appMenu.items.firstIndex { item in
            if item.keyEquivalent == "," {
                return true
            }
            let title = item.title.lowercased()
            return title.hasPrefix("设置") || title.hasPrefix("setting")
        }

        guard let index else {
            return false
        }

        appMenu.performActionForItem(at: index)
        return true
    }
}

/// Puts a working "设置…" item in the app menu.
///
/// `SettingsLink` is what SwiftUI supports for opening a `Settings` scene, and
/// it has to be a view — which a menu item can be.
struct SettingsMenuButton: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Text("设置…")
            }
            .keyboardShortcut(",", modifiers: .command)
            .onAppear {
                DiagnosticsLog.log("settings: menu item appeared")
            }
        } else {
            Button("设置…") {
                SettingsOpener.show()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

/// Hands `openSettings` to `SettingsOpener` without needing macOS 14 at the
/// call site: the deployment target is macOS 13, where the environment action
/// does not exist.
struct SettingsActionExporter: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            OpenSettingsExporter()
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

@available(macOS 14.0, *)
private struct OpenSettingsExporter: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                SettingsOpener.adopt { openSettings() }
            }
    }
}
