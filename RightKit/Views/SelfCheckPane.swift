import AppKit
import SwiftUI

/// 自检页。首次运行时也会自动打开这里，所以它同时充当首次设置引导：
/// 每一行就是一项该配好的东西，缺什么当场给一个按钮。
struct SelfCheckPane: View {
    @EnvironmentObject private var store: SettingsStore

    @State private var results: [HealthCheckResult] = []

    var body: some View {
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
                Button("检查") { refresh() }
                    .help("改完系统设置后回来点一下")
            }
        }
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
