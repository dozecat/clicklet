import Foundation

/// 自检的输入。
///
/// 刻意做成一个纯数据结构：所有检查逻辑因此可以完全脱离真实系统来测试，
/// 不用去改权限、启停扩展。真正的状态由 `SettingsStore` / `AppGroupStore` 填进来。
struct HealthCheckInput {
    var extensionEnabled: Bool
    var accessibilityGranted: Bool
    var notificationsGranted: Bool
    var appGroupAvailable: Bool
    /// 菜单快照的最后写入时间；nil 表示从未写过。
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

/// 一项自检的结果。
struct HealthCheckResult: Identifiable, Equatable {
    enum Level: Equatable {
        case ok
        case warning
        case failed
    }

    /// 能一键解决时给出的动作。
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
    /// 快照超过这个时长就提示一次——菜单没更新是真实发生过的故障。
    static let snapshotStaleAfter: TimeInterval = 24 * 60 * 60

    static func run(_ input: HealthCheckInput) -> [HealthCheckResult] {
        [
            extensionCheck(input),
            accessibilityCheck(input),
            notificationCheck(input),
            appGroupCheck(input),
            snapshotCheck(input),
            compressorCheck(input),
            scriptsCheck(input)
        ]
    }

    // MARK: - 逐项

    private static func extensionCheck(_ input: HealthCheckInput) -> HealthCheckResult {
        HealthCheckResult(
            id: "extension",
            title: "访达扩展",
            level: input.extensionEnabled ? .ok : .failed,
            detail: input.extensionEnabled ? "已启用" : "未启用，右键菜单不会出现",
            fix: input.extensionEnabled ? nil : .openExtensionSettings,
            fixTitle: input.extensionEnabled ? nil : "去启用"
        )
    }

    private static func accessibilityCheck(_ input: HealthCheckInput) -> HealthCheckResult {
        HealthCheckResult(
            id: "accessibility",
            title: "辅助功能",
            level: input.accessibilityGranted ? .ok : .warning,
            detail: input.accessibilityGranted
                ? "已授权，新建文件会自动进入重命名"
                : "未授权，新建文件后需要自己按回车改名",
            fix: input.accessibilityGranted ? nil : .requestAccessibility,
            fixTitle: input.accessibilityGranted ? nil : "去授权"
        )
    }

    private static func notificationCheck(_ input: HealthCheckInput) -> HealthCheckResult {
        HealthCheckResult(
            id: "notifications",
            title: "通知",
            level: input.notificationsGranted ? .ok : .warning,
            detail: input.notificationsGranted ? "已授权" : "未授权，脚本结果不会提示",
            fix: input.notificationsGranted ? nil : .requestNotifications,
            fixTitle: input.notificationsGranted ? nil : "去授权"
        )
    }

    private static func appGroupCheck(_ input: HealthCheckInput) -> HealthCheckResult {
        HealthCheckResult(
            id: "appGroup",
            title: "共享容器",
            level: input.appGroupAvailable ? .ok : .failed,
            detail: input.appGroupAvailable
                ? "可读写"
                : "不可用：主 App 与扩展无法交换数据",
            fix: nil,
            fixTitle: nil
        )
    }

    private static func snapshotCheck(_ input: HealthCheckInput) -> HealthCheckResult {
        guard let age = input.snapshotAge else {
            return HealthCheckResult(
                id: "snapshot",
                title: "菜单快照",
                level: .failed,
                detail: "还没有生成过，右键菜单会是空的",
                fix: nil,
                fixTitle: nil
            )
        }

        if age > snapshotStaleAfter {
            let hours = Int(age / 3600)
            return HealthCheckResult(
                id: "snapshot",
                title: "菜单快照",
                level: .warning,
                detail: "已有 \(hours) 小时没更新，改动可能没生效",
                fix: nil,
                fixTitle: nil
            )
        }

        return HealthCheckResult(
            id: "snapshot",
            title: "菜单快照",
            level: .ok,
            detail: "是新的",
            fix: nil,
            fixTitle: nil
        )
    }

    private static func compressorCheck(_ input: HealthCheckInput) -> HealthCheckResult {
        HealthCheckResult(
            id: "compressor",
            title: "压缩工具",
            level: input.compressorInstalled ? .ok : .warning,
            detail: input.compressorInstalled
                ? "已找到所选压缩器"
                : "没找到所选压缩器，压缩解压不可用",
            fix: nil,
            fixTitle: nil
        )
    }

    private static func scriptsCheck(_ input: HealthCheckInput) -> HealthCheckResult {
        HealthCheckResult(
            id: "scriptsDirectory",
            title: "脚本目录",
            level: input.scriptsDirectoryWritable ? .ok : .failed,
            detail: input.scriptsDirectoryWritable ? "可写入" : "不可写，脚本无法安装",
            fix: input.scriptsDirectoryWritable ? nil : .revealLogs,
            fixTitle: input.scriptsDirectoryWritable ? nil : "查看日志"
        )
    }

    /// 有失败项时给一句话总结，供界面顶部使用。
    static func summary(_ results: [HealthCheckResult]) -> String {
        let failed = results.filter { $0.level == .failed }.count
        let warnings = results.filter { $0.level == .warning }.count
        if failed > 0 { return "有 \(failed) 项需要处理" }
        if warnings > 0 { return "有 \(warnings) 项建议开启" }
        return "一切正常"
    }
}
