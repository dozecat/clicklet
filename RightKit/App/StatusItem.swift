import AppKit
import SwiftUI

/// The status bar item.
///
/// There is no Dock icon (`LSUIElement`), so settings are reached from here:
/// one click, instead of digging through Finder's context menu.
struct StatusItemLabel: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        // The icon itself carries the state. When the Finder extension is
        // switched off the whole context menu disappears, which is the worst
        // failure this app has, so the icon has to say so at a glance instead
        // of always looking the same.
        //
        // Normally it is a simplified outline of the app icon (rounded square
        // plus cursor) rather than a generic cursor symbol, which would not
        // read as RightKit. When the extension is off it becomes a warning
        // triangle, because at that point the menu is gone.
        if store.finderMenuState == .enabled {
            Image(nsImage: StatusItemImage.normal)
        } else {
            Image(systemName: "exclamationmark.triangle")
        }
    }
}

/// The status bar menu. Deliberately only three things: open settings, check
/// status, quit.
struct StatusItemMenu: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        // Uses SettingsLink rather than SettingsOpener.show(): this is the route
        // SwiftUI actually supports, and it needs no AppKit plumbing, so it
        // cannot be affected by LSUIElement. That matters because this is now the
        // only guaranteed way into the app.
        if #available(macOS 14.0, *) {
            SettingsLink {
                L.t("打开设置…")
            }
            .keyboardShortcut(",", modifiers: .command)
        } else {
            Button { SettingsOpener.show() } label: { L.t("打开设置…") }
                .keyboardShortcut(",", modifiers: .command)
        }

        Divider()

        Button { NSApp.terminate(nil) } label: { L.t("退出 RightKit") }
            .keyboardShortcut("q", modifiers: .command)
    }
}
