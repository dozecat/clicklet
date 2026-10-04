import Foundation

/// The input to the self-check.
///
/// Deliberately a plain data structure: all the check logic can therefore be
/// tested completely independently of the real system, without changing
/// permissions or enabling/disabling the extension. The real state is filled in
/// by `SettingsStore` / `AppGroupStore`.
struct HealthCheckInput {
    var extensionEnabled: Bool
    var accessibilityGranted: Bool
    var notificationsGranted: Bool
    var appGroupAvailable: Bool
    /// When the menu snapshot was last written; nil means it was never written.
    var snapshotAge: TimeInterval?
    var compressorInstalled: Bool
    var scriptsDirectoryWritable: Bool

    init(
        extensionEnabled: Bool = false,
        accessibilityGranted: Bool = false,
        notificationsGranted: Bool = false,
        appGroupAvailable: Bool = false,
        snapshotAge: TimeInterval? = nil,
        compressorInstalled: Bool = false,
        scriptsDirectoryWritable: Bool = false
    ) {
        self.extensionEnabled = extensionEnabled
        self.accessibilityGranted = accessibilityGranted
        self.notificationsGranted = notificationsGranted
        self.appGroupAvailable = appGroupAvailable
        self.snapshotAge = snapshotAge
        self.compressorInstalled = compressorInstalled
        self.scriptsDirectoryWritable = scriptsDirectoryWritable
    }
}

/// The result of one self-check item.
struct HealthCheckResult: Identifiable, Equatable {
    enum Level: Equatable {
        case ok
        case warning
        case failed
    }

    /// The action offered when the problem can be fixed in one click.
    enum Fix: Equatable {
        case openExtensionSettings
        case requestAccessibility
        case requestNotifications
        case revealLogs
    }

    let id: String
    let title: String
    let level: Level
    let detail: String
    let fix: Fix?
    let fixTitle: String?
}

enum HealthCheck {
    /// Warn once the snapshot is older than this — a menu that stopped updating is
    /// a failure that has really happened.
    static let snapshotStaleAfter: TimeInterval = 24 * 60 * 60

    /// The language is a parameter rather than a global read, because the check is a
    /// pure function: the tests drive it with no settings store at all. The source
    /// language is the default, so a caller that passes nothing gets the catalog
    /// keys back unchanged.
    static func run(
        _ input: HealthCheckInput,
        language: AppLanguage = .simplifiedChinese
    ) -> [HealthCheckResult] {
        [
            extensionCheck(input, language: language),
            accessibilityCheck(input, language: language),
            notificationCheck(input, language: language),
            appGroupCheck(input, language: language),
            snapshotCheck(input, language: language),
            compressorCheck(input, language: language),
            scriptsCheck(input, language: language)
        ]
    }

    // MARK: - Individual checks

    private static func extensionCheck(
        _ input: HealthCheckInput,
        language: AppLanguage
    ) -> HealthCheckResult {
        HealthCheckResult(
            id: "extension",
            title: LocalizedText.string("访达扩展", language: language),
            level: input.extensionEnabled ? .ok : .failed,
            detail: LocalizedText.string(
                input.extensionEnabled ? "已启用" : "未启用，右键菜单不会出现",
                language: language
            ),
            fix: input.extensionEnabled ? nil : .openExtensionSettings,
            fixTitle: input.extensionEnabled
                ? nil
                : LocalizedText.string("去启用", language: language)
        )
    }

    private static func accessibilityCheck(
        _ input: HealthCheckInput,
        language: AppLanguage
    ) -> HealthCheckResult {
        HealthCheckResult(
            id: "accessibility",
            title: LocalizedText.string("辅助功能", language: language),
            level: input.accessibilityGranted ? .ok : .warning,
            detail: LocalizedText.string(
                input.accessibilityGranted
                    ? "已授权，新建文件会自动进入重命名"
                    : "未授权，新建文件后需要自己按回车改名",
                language: language
            ),
            fix: input.accessibilityGranted ? nil : .requestAccessibility,
            fixTitle: input.accessibilityGranted
                ? nil
                : LocalizedText.string("去授权", language: language)
        )
    }

    private static func notificationCheck(
        _ input: HealthCheckInput,
        language: AppLanguage
    ) -> HealthCheckResult {
        HealthCheckResult(
            id: "notifications",
            title: LocalizedText.string("通知", language: language),
            level: input.notificationsGranted ? .ok : .warning,
            detail: LocalizedText.string(
                input.notificationsGranted ? "已授权" : "未授权，脚本结果不会提示",
                language: language
            ),
            fix: input.notificationsGranted ? nil : .requestNotifications,
            fixTitle: input.notificationsGranted
                ? nil
                : LocalizedText.string("去授权", language: language)
        )
    }

    private static func appGroupCheck(
        _ input: HealthCheckInput,
        language: AppLanguage
    ) -> HealthCheckResult {
        HealthCheckResult(
            id: "appGroup",
            title: LocalizedText.string("共享容器", language: language),
            level: input.appGroupAvailable ? .ok : .failed,
            detail: LocalizedText.string(
                input.appGroupAvailable
                    ? "可读写"
                    : "不可用：主 App 与扩展无法交换数据",
                language: language
            ),
            fix: nil,
            fixTitle: nil
        )
    }

    private static func snapshotCheck(
        _ input: HealthCheckInput,
        language: AppLanguage
    ) -> HealthCheckResult {
        let title = LocalizedText.string("菜单快照", language: language)

        guard let age = input.snapshotAge else {
            return HealthCheckResult(
                id: "snapshot",
                title: title,
                level: .failed,
                detail: LocalizedText.string(
                    "还没有生成过，右键菜单会是空的",
                    language: language
                ),
                fix: nil,
                fixTitle: nil
            )
        }

        if age > snapshotStaleAfter {
            let hours = Int(age / 3600)
            return HealthCheckResult(
                id: "snapshot",
                title: title,
                level: .warning,
                detail: String(
                    format: LocalizedText.string(
                        "已有 %lld 小时没更新，改动可能没生效",
                        language: language
                    ),
                    hours
                ),
                fix: nil,
                fixTitle: nil
            )
        }

        return HealthCheckResult(
            id: "snapshot",
            title: title,
            level: .ok,
            detail: LocalizedText.string("是新的", language: language),
            fix: nil,
            fixTitle: nil
        )
    }

    private static func compressorCheck(
        _ input: HealthCheckInput,
        language: AppLanguage
    ) -> HealthCheckResult {
        HealthCheckResult(
            id: "compressor",
            title: LocalizedText.string("压缩工具", language: language),
            level: input.compressorInstalled ? .ok : .warning,
            detail: LocalizedText.string(
                input.compressorInstalled
                    ? "已找到所选压缩器"
                    : "没找到所选压缩器，压缩解压不可用",
                language: language
            ),
            fix: nil,
            fixTitle: nil
        )
    }

    private static func scriptsCheck(
        _ input: HealthCheckInput,
        language: AppLanguage
    ) -> HealthCheckResult {
        HealthCheckResult(
            id: "scriptsDirectory",
            title: LocalizedText.string("脚本目录", language: language),
            level: input.scriptsDirectoryWritable ? .ok : .failed,
            detail: LocalizedText.string(
                input.scriptsDirectoryWritable ? "可写入" : "不可写，脚本无法安装",
                language: language
            ),
            fix: input.scriptsDirectoryWritable ? nil : .revealLogs,
            fixTitle: input.scriptsDirectoryWritable
                ? nil
                : LocalizedText.string("查看日志", language: language)
        )
    }

    /// A one-line summary when something failed, used at the top of the UI.
    ///
    /// The count goes through `%lld` rather than into the key, so one catalog entry
    /// covers every number. The default language keeps the source-language result
    /// the tests pin down.
    static func summary(
        _ results: [HealthCheckResult],
        language: AppLanguage = .simplifiedChinese
    ) -> String {
        let failed = results.filter { $0.level == .failed }.count
        let warnings = results.filter { $0.level == .warning }.count
        if failed > 0 {
            return String(
                format: LocalizedText.string("有 %lld 项需要处理", language: language),
                failed
            )
        }
        if warnings > 0 {
            return String(
                format: LocalizedText.string("有 %lld 项建议开启", language: language),
                warnings
            )
        }
        return LocalizedText.string("一切正常", language: language)
    }
}
