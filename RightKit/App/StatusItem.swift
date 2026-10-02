import AppKit
import SwiftUI

/// 状态栏图标。
///
/// Dock 图标没有了（`LSUIElement`），设置从这里进——点一下就能开，
/// 不用去访达右键菜单里翻。
struct StatusItemLabel: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        // 图标本身反映状态。访达扩展被系统关掉时右键菜单会整个消失，
        // 那是最要命的故障，所以图标得能立刻告诉用户"有事"，而不是永远长一样。
        // 正常状态用简化过的 App 图标轮廓（圆角方块 + 光标），
        // 而不是通用光标符号——后者看不出这是 RightKit。
        // 扩展被关掉时换成警示三角，因为那时候右键菜单整个消失。
        if store.finderMenuState == .enabled {
            Image(nsImage: StatusItemImage.normal)
        } else {
            Image(systemName: "exclamationmark.triangle")
        }
    }
}

/// 状态栏下拉菜单。刻意只放三件事：开设置、看自检、退出。
struct StatusItemMenu: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        // Uses SettingsLink rather than SettingsOpener.show(): this is the route
        // SwiftUI actually supports, and it needs no AppKit plumbing, so it
        // cannot be affected by LSUIElement. That matters because this is now the
        // only guaranteed way into the app.
        if #available(macOS 14.0, *) {
            SettingsLink {
                Text("打开设置…")
            }
            .keyboardShortcut(",", modifiers: .command)
        } else {
            Button("打开设置…") { SettingsOpener.show() }
                .keyboardShortcut(",", modifiers: .command)
        }

        Button("检查运行状态…") {
            store.showHealthCheck()
            SettingsOpener.show()
        }

        Divider()

        Button("退出 RightKit") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
