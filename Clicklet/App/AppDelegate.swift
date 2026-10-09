import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticsLog.log(
            "app launched; version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") "
                + "appGroup=\(AppGroup.identifier) container=\(AppGroup.containerURL?.path ?? "UNAVAILABLE")"
        )
        // First run: open the settings window on the self-check page — that page is
        // the first-run setup guide, since whatever is missing has a button right
        // there and there is no need for a separate wizard.
        //
        // But do not pop a window when the launch came from a Finder action: that
        // kind of launch should just do the work quietly and drop back into the
        // background, while a window would land right in front of the user.
        // The marker is written when the user finishes the sheet, not here. Marking it
        // up front meant that quitting before the permissions were granted retired the
        // guide for good — the exact complaint this fixes.
        if !AppGroupStore.hasCompletedFirstRun {
            if AppGroupStore.pendingActionRequestIDs().isEmpty {
                OnboardingWindow.shared.show()
                DiagnosticsLog.log("first run: showing the onboarding guide")
            }
        }

        // After a reboot Finder will not load the extension until its election changes,
        // which is why the menu used to be missing until the switch in System Settings
        // was toggled. Do that half-flip here instead, quietly.
        FinderExtensionController.reelect()

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
            NSLog("Clicklet catalog refresh failed: %@", error.localizedDescription)
        }
        ActionCoordinator.shared.start()
        NotificationService.shared.requestAuthorization()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        DiagnosticsLog.log("app received urls: \(urls.map(\.absoluteString))")
        NSLog("Clicklet received URLs: %@", urls.map(\.absoluteString))
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
