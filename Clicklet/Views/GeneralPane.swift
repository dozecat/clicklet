import AppKit
import SwiftUI

struct GeneralPane: View {
    @EnvironmentObject private var store: SettingsStore
    @State private var isConfirmingReset = false


    var body: some View {
        SettingsPane {
            PermissionSummaryBanner()

            SettingsSection {
            SettingsRow("登录时启动") {
                SettingsCheckbox(
                    title: store.launchAtLogin ? "打开" : "关闭",
                    isOn: Binding(
                        get: { store.launchAtLogin },
                        set: { store.setLaunchAtLogin($0) }
                    )
                )
                .help(L.t("开机后自动运行，右键菜单无需手动启动"))
            }

            SettingsRow("语言") {
                HStack(spacing: 10) {
                    Picker("", selection: Binding(
                        get: { store.preferences.resolvedLanguage },
                        set: { store.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            // "Follow System" needs translating; "Simplified Chinese"
                            // and "English" are written natively in their own languages
                            // and are not in the catalog, so they display as-is.
                            // Language names are shown in their own language on purpose, so they must not
                            // be looked up as translation keys.
                            Text(verbatim: language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
            }

            SettingsGroupSeparator()

            SettingsSection {
            SettingsRow("访达扩展") {
                if store.finderMenuState == .unknown {
                    Button { store.openExtensionSettings() } label: { L.t("打开系统设置…") }
                } else {
                    SettingsCheckbox(
                        title: store.finderMenuState == .enabled ? "打开" : "关闭",
                        isOn: Binding(
                            get: { store.finderMenuState == .enabled },
                            set: { store.setFinderMenuEnabled($0) }
                        ),
                        showsStatusDot: true
                    )
                    .help(L.t("关闭后 Finder 中不再出现 Clicklet 菜单"))
                }
            }

            SettingsRow("辅助功能") {
                HStack(spacing: 6) {
                    SettingsStatusDot(isOn: store.canAutoRename)

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
                }
                .help(L.t("授权后新建文件会自动进入重命名状态"))
            }

            SettingsRow("通知") {
                HStack(spacing: 6) {
                    SettingsStatusDot(isOn: store.notificationsAuthorized)
                    SettingsValue(text: store.notificationsAuthorized ? "已授权" : "未授权")
                }
            }
            }

            SettingsGroupSeparator()

            SettingsSection {
            SettingsRow("脚本目录") {
                Button { store.revealScriptsDirectory() } label: { L.t("显示") }
                    .help(shortenedPath(store.scriptsDirectory.path))
            }

            if let templatesDirectory = store.userTemplatesDirectory, store.hasUserTemplates {
                SettingsRow("模板目录") {
                    Button { store.revealTemplatesDirectory() } label: { L.t("显示") }
                        .help(shortenedPath(templatesDirectory.path))
                }
            }
            }

            SettingsGroupSeparator()

            SettingsSection {
            SettingsRow("重置设置") {
                Button { isConfirmingReset = true } label: { L.t("恢复出厂设置…") }
            }
            }
        }
        .confirmationDialog(
            // A String, not a LocalizedStringKey: the key overload consults
            // Bundle.main, whose language is fixed at launch, so the dialog would
            // stay in the old language after a switch.
            LocalizedText.string(
                "恢复出厂设置？",
                language: LocalizedText.currentLanguage
            ),
            isPresented: $isConfirmingReset
        ) {
            Button(role: .destructive) { store.resetToDefaults() } label: { L.t("恢复") }
            Button(role: .cancel) {} label: { L.t("取消") }
        } message: {
            L.t("所有启用开关与排序会回到默认，压缩软件恢复为默认选择。")
                 + L.t("脚本包、图标与模板文件不会被删除。")
        }
    }

}
