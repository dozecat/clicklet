import XCTest

/// The self-check is a pure function: state in, verdict out. So these tests never
/// have to actually change permissions or enable/disable the extension.
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

    /// A disabled extension is the most serious item: the right-click menu will not
    /// appear at all.
    func testExtensionDisabledIsFailureWithFix() {
        var input = healthy()
        input.extensionEnabled = false
        let results = HealthCheck.run(input)
        let item = results.first { $0.id == "extension" }
        XCTAssertEqual(item?.level, .failed)
        XCTAssertEqual(item?.fix, .openExtensionSettings)
        XCTAssertEqual(HealthCheck.summary(results), "有 1 项需要处理")
    }

    /// Accessibility and notifications are "recommended", not fatal.
    func testOptionalPermissionsAreWarnings() {
        var input = healthy()
        input.accessibilityGranted = false
        input.notificationsGranted = false
        let results = HealthCheck.run(input)
        XCTAssertEqual(results.first { $0.id == "accessibility" }?.level, .warning)
        XCTAssertEqual(results.first { $0.id == "notifications" }?.level, .warning)
        XCTAssertEqual(HealthCheck.summary(results), "有 2 项建议开启")
    }

    /// The snapshot was never written → failure; not updated for too long → warning.
    func testSnapshotFreshness() {
        var input = healthy()
        input.snapshotAge = nil
        XCTAssertEqual(HealthCheck.run(input).first { $0.id == "snapshot" }?.level, .failed)

        input.snapshotAge = HealthCheck.snapshotStaleAfter + 60
        XCTAssertEqual(HealthCheck.run(input).first { $0.id == "snapshot" }?.level, .warning)

        input.snapshotAge = HealthCheck.snapshotStaleAfter - 60
        XCTAssertEqual(HealthCheck.run(input).first { $0.id == "snapshot" }?.level, .ok)
    }

    /// An unavailable shared container is fatal, and there is no one-click fix — it
    /// can only be reported.
    func testAppGroupFailureHasNoFix() {
        var input = healthy()
        input.appGroupAvailable = false
        let item = HealthCheck.run(input).first { $0.id == "appGroup" }
        XCTAssertEqual(item?.level, .failed)
        XCTAssertNil(item?.fix)
    }

    /// Every item's id is unique; the UI uses the id for ForEach.
    func testIdentifiersAreUnique() {
        let ids = HealthCheck.run(healthy()).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
