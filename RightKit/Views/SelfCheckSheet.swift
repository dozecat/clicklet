import AppKit
import SwiftUI

/// 自检面板（sheet）。
///
/// 不占页签：设置是"配置"，自检是"排查"，两者心智不同；而且自检的常态是
/// "一切正常"，一个永远说废话的页签不值得占位置。
/// 首次运行时自动弹一次，之后从「帮助 → 检查运行状态…」叫出来。
struct SelfCheckSheet: View {
    @EnvironmentObject private var store: SettingsStore

    @State private var results: [HealthCheckResult] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                L.t("检查运行状态")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            SettingsPane {
                SettingsRow("总体") {
                    SettingsValue(text: results.isEmpty ? "检查中…" : HealthCheck.summary(results))
                }

                SettingsGroupSeparator()

                ForEach(results) { result in
                    SettingsRow(result.title) {
                        HStack(spacing: 8) {
                            Image(systemName: symbol(for: result.level))
                                .foregroundStyle(colour(for: result.level))
                            SettingsValue(text: result.detail)
                            if let fix = result.fix, let title = result.fixTitle {
                                Button(title) { perform(fix) }
                            }
                        }
                    }
                }

                SettingsGroupSeparator()

                SettingsRow("重新检查") {
                    Button { refresh() } label: { L.t("检查") }
                        .help(L.t("改完系统设置后回来点一下"))
                }
            }
            Divider()

            HStack {
                Spacer()
                Button { store.dismissHealthCheck() } label: { L.t("完成") }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        // 高度按内容给足：辅助功能那行说明会换两行，440 时最后一项会被裁掉。
        .frame(width: 620, height: 520)
        .onAppear { refresh() }
        .onReceive(store.$finderMenuState) { _ in refresh() }
        .onReceive(store.$canAutoRename) { _ in refresh() }
        .onReceive(store.$notificationsAuthorized) { _ in refresh() }
    }

    /// 把真实状态灌进纯数据结构；检查逻辑本身不碰系统。
    private func refresh() {
        let snapshotAge = AppGroupStore.menuSnapshotModificationDate()
            .map { Date().timeIntervalSince($0) }

        results = HealthCheck.run(
            HealthCheckInput(
                extensionEnabled: store.finderMenuState == .enabled,
                accessibilityGranted: store.canAutoRename,
                notificationsGranted: store.notificationsAuthorized,
                appGroupAvailable: AppGroup.containerURL != nil,
                snapshotAge: snapshotAge,
                compressorInstalled: CompressionService.shared.selectedCompressor.isInstalled,
                scriptsDirectoryWritable: FileManager.default.isWritableFile(
                    atPath: AppPaths.scriptsDirectory.path
                )
            )
        )
    }

    private func perform(_ fix: HealthCheckResult.Fix) {
        switch fix {
        case .openExtensionSettings:
            store.openExtensionSettings()
        case .requestAccessibility:
            FinderRenameService.requestPermission()
        case .requestNotifications:
            NotificationService.shared.requestAuthorization()
        case .revealLogs:
            NSWorkspace.shared.open(AppPaths.logsDirectory)
        }
        // 授权类动作要跳系统设置，回来时状态会变，靠 onReceive 自动重查。
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { refresh() }
    }

    private func symbol(for level: HealthCheckResult.Level) -> String {
        switch level {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func colour(for level: HealthCheckResult.Level) -> Color {
        switch level {
        case .ok: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }
}
