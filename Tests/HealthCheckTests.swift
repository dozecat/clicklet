import XCTest

/// 自检是纯函数：输入状态、输出结论。所以这些测试不用真去改权限或启停扩展。
final class HealthCheckTests: XCTestCase {
    private func healthy() -> HealthCheckInput {
        HealthCheckInput(
            extensionEnabled: true,
            accessibilityGranted: true,
            notificationsGranted: true,
            appGroupAvailable: true,
            snapshotAge: 60,
            compressorInstalled: true,
            scriptsDirectoryWritable: true
        )
    }

    func testAllGreen() {
        let results = HealthCheck.run(healthy())
        XCTAssertEqual(results.count, 7)
        XCTAssertTrue(results.allSatisfy { $0.level == .ok })
        XCTAssertEqual(HealthCheck.summary(results), "一切正常")
        XCTAssertTrue(results.allSatisfy { $0.fix == nil }, "没问题时不该给按钮")
    }

    /// 扩展没启用是最严重的一项：右键菜单根本不会出现。
    func testExtensionDisabledIsFailureWithFix() {
        var input = healthy()
        input.extensionEnabled = false
        let results = HealthCheck.run(input)
        let item = results.first { $0.id == "extension" }
        XCTAssertEqual(item?.level, .failed)
        XCTAssertEqual(item?.fix, .openExtensionSettings)
        XCTAssertEqual(HealthCheck.summary(results), "有 1 项需要处理")
    }

    /// 辅助功能与通知是"建议开启"，不是致命项。
    func testOptionalPermissionsAreWarnings() {
        var input = healthy()
        input.accessibilityGranted = false
        input.notificationsGranted = false
        let results = HealthCheck.run(input)
        XCTAssertEqual(results.first { $0.id == "accessibility" }?.level, .warning)
        XCTAssertEqual(results.first { $0.id == "notifications" }?.level, .warning)
        XCTAssertEqual(HealthCheck.summary(results), "有 2 项建议开启")
    }

    /// 从来没写过快照 → 失败；太久没更新 → 警告。
    func testSnapshotFreshness() {
        var input = healthy()
        input.snapshotAge = nil
        XCTAssertEqual(HealthCheck.run(input).first { $0.id == "snapshot" }?.level, .failed)

        input.snapshotAge = HealthCheck.snapshotStaleAfter + 60
        XCTAssertEqual(HealthCheck.run(input).first { $0.id == "snapshot" }?.level, .warning)

        input.snapshotAge = HealthCheck.snapshotStaleAfter - 60
        XCTAssertEqual(HealthCheck.run(input).first { $0.id == "snapshot" }?.level, .ok)
    }

    /// 共享容器不可用是致命的，而且没有一键修复——只能报出来。
    func testAppGroupFailureHasNoFix() {
        var input = healthy()
        input.appGroupAvailable = false
        let item = HealthCheck.run(input).first { $0.id == "appGroup" }
        XCTAssertEqual(item?.level, .failed)
        XCTAssertNil(item?.fix)
    }

    /// 每一项的 id 唯一，界面用 id 做 ForEach。
    func testIdentifiersAreUnique() {
        let ids = HealthCheck.run(healthy()).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
