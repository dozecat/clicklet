import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 界面语言必须在**任何** SwiftUI 文案被解析之前写进去，所以放在
    /// willFinishLaunching 而不是 didFinishLaunching——后者往往已经太晚，
    /// 那就得重启才看得到效果。
    func applicationWillFinishLaunching(_ notification: Notification) {
        let language = AppGroupStore.loadPreferences().resolvedLanguage
        UserDefaults.standard.set([language.lprojCode], forKey: "AppleLanguages")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticsLog.log(
            "app launched; version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") "
                + "appGroup=\(AppGroup.identifier) container=\(AppGroup.containerURL?.path ?? "UNAVAILABLE")"
        )
        // 首次运行：把设置窗口开在自检页——那一页就是首次设置引导，
        // 缺什么当场有按钮，不用再单独做一个向导。
        //
        // 但被右键动作唤起时不要弹窗：那种启动只该安静做完活然后退回后台，
        // 弹窗会正好挡在用户面前。
        if !AppGroupStore.hasCompletedFirstRun {
            AppGroupStore.markFirstRunCompleted()
            if AppGroupStore.pendingActionRequestIDs().isEmpty {
                SettingsStore.shared.showHealthCheck()
                SettingsOpener.show()
                DiagnosticsLog.log("first run: showing the health check sheet")
            }
        }

        let seeded = BuiltinScriptSeeder.seedIfNeeded()
        if !seeded.isEmpty {
            DiagnosticsLog.log("built-in scripts offered: \(seeded)")
        }

        do {
            let snapshot = try ScriptCatalogService.shared.refresh()
            DiagnosticsLog.log(
                "catalog refreshed: templates=\(snapshot.templates.map(\.id)) scripts=\(snapshot.scripts.count)"
            )
        } catch {
            DiagnosticsLog.log("catalog refresh failed: \(error.localizedDescription)")
            NSLog("RightKit catalog refresh failed: %@", error.localizedDescription)
        }
        ActionCoordinator.shared.start()
        NotificationService.shared.requestAuthorization()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        DiagnosticsLog.log("app received urls: \(urls.map(\.absoluteString))")
        NSLog("RightKit received URLs: %@", urls.map(\.absoluteString))
        urls.forEach {
            ActionCoordinator.shared.handle(url: $0)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        // There is no window at launch any more, so clicking the Dock icon has to
        // be what brings the settings window up.
        if !flag {
            SettingsOpener.show()
        }
        return true
    }

    /// macOS reopens the windows an app had when it last quit. For a utility that
    /// is woken by Finder actions, that means the settings window reappears the
    /// next time an action runs — it looks like the app woke the window itself,
    /// and it flashes on every action while the window is already open.
    ///
    /// Turning restoration off at the application level rather than per scene:
    /// SwiftUI's `.restorationBehavior` needs macOS 15, and `SceneBuilder` cannot
    /// express an availability check.
    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        ActionCoordinator.shared.invalidate()
    }
}
