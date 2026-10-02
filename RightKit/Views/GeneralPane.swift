import AppKit
import SwiftUI

struct GeneralPane: View {
    @EnvironmentObject private var store: SettingsStore
    @State private var isConfirmingReset = false

    var body: some View {
        SettingsPane {
            SettingsRow("登录时启动") {
                SettingsCheckbox(
                    title: store.launchAtLogin ? "打开" : "关闭",
                    isOn: Binding(
                        get: { store.launchAtLogin },
                        set: { store.setLaunchAtLogin($0) }
                    )
                )
                .help("开机后自动运行，右键菜单无需手动启动")
            }

            SettingsRow("语言") {
                SettingsValue(text: "简体中文")
            }

            SettingsGroupSeparator()

            SettingsRow("访达拓展") {
                if store.finderMenuState == .unknown {
                    Button("打开系统设置…") { openExtensionSettings() }
                } else {
                    SettingsCheckbox(
                        title: store.finderMenuState == .enabled ? "打开" : "关闭",
                        isOn: Binding(
                            get: { store.finderMenuState == .enabled },
                            set: { store.setFinderMenuEnabled($0) }
                        )
                    )
                    .help("关闭后 Finder 中不再出现 RightKit 菜单")
                }
            }

            SettingsRow("辅助功能") {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { store.canAutoRename },
                        set: { if $0 { store.requestRenamePermission() } }
                    )
                )
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(store.canAutoRename)
                .help("授权后新建文件会自动进入重命名状态")
            }

            SettingsRow("通知") {
                SettingsValue(text: store.notificationsAuthorized ? "已授权" : "未授权")
            }

            SettingsGroupSeparator()

            SettingsRow("脚本目录") {
                Button("显示") { store.revealScriptsDirectory() }
                    .help(shortenedPath(store.scriptsDirectory.path))
            }

            if let templatesDirectory = store.userTemplatesDirectory {
                SettingsRow("模板目录") {
                    Button("显示") { store.revealTemplatesDirectory() }
                        .help(shortenedPath(templatesDirectory.path))
                }
            }

            SettingsGroupSeparator()

            SettingsRow("重置设置") {
                Button("恢复出厂设置…") { isConfirmingReset = true }
            }
        }
        .confirmationDialog(
            "恢复出厂设置？",
            isPresented: $isConfirmingReset
        ) {
            Button("恢复", role: .destructive) { store.resetToDefaults() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有启用开关与排序会回到默认，压缩软件恢复为默认选择。"
                 + "脚本包、图标与模板文件不会被删除。")
        }
    }

    private func openExtensionSettings() {
        // Ventura and later moved extensions into "Login Items & Extensions";
        // the older pane identifier is kept as a fallback.
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
