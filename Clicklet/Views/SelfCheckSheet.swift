import AppKit
import SwiftUI

/// The self-check panel (a sheet).
///
/// It does not take a tab: settings are "configuration" and the self-check is
/// "troubleshooting", two different mindsets; and on top of that the self-check is
/// normally "everything is fine", so a tab that always states the obvious is not
/// worth a slot.
/// It pops up automatically on first run, and afterwards is summoned from
/// "Help → Check Status…".
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
                    SettingsValue(
                        text: results.isEmpty
                            ? "检查中…"
                            : HealthCheck.summary(
                                results,
                                language: LocalizedText.currentLanguage
                            )
                    )
                }

                SettingsGroupSeparator()

                ForEach(results) { result in
                    SettingsRow(result.title) {
                        HStack(spacing: 8) {
                            Image(systemName: symbol(for: result.level))
                                .foregroundStyle(colour(for: result.level))
                            SettingsValue(text: result.detail)
                            if let fix = result.fix, let title = result.fixTitle {
                                Button { perform(fix) } label: { L.t(title) }
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
                Button { SelfCheckWindow.shared.close() } label: { L.t("完成") }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        // Give the height enough room for the content: the accessibility
        // explanation wraps onto two lines, and at 440 the last item gets clipped.
        .frame(width: 620, height: 520)
        .onAppear { refresh() }
        .onReceive(store.$finderMenuState) { _ in refresh() }
        .onReceive(store.$canAutoRename) { _ in refresh() }
        .onReceive(store.$notificationsAuthorized) { _ in refresh() }
    }

    /// Feeds the real state into the plain data structure; the check logic itself
    /// never touches the system.
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
            ),
            language: LocalizedText.currentLanguage
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
        // Permission actions have to jump to System Settings, and the state changes
        // by the time the user comes back; onReceive re-checks automatically.
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
