import AppKit
import Foundation
import SwiftUI
import UserNotifications

/// Owns the settings window's state and is the single place that writes user
/// preferences back to the App Group and regenerates the Finder menu snapshot.
///
/// Before this existed nothing ever called `AppGroupStore.savePreferences`, so
/// every change in the settings window was discarded and the Finder menu never
/// changed.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published private(set) var preferences = AppPreferences()
    @Published private(set) var templates: [FileTemplate] = []
    @Published private(set) var scripts: [ScriptPackage] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var finderMenuState: FinderExtensionController.State = .unknown
    @Published private(set) var canAutoRename = FinderRenameService.isPermitted
    @Published private(set) var notificationsAuthorized = false
    @Published private(set) var launchAtLogin = LaunchAtLoginService.state == .enabled

    /// The self-check appears as a sheet and does not take a tab: settings are
    /// "configuration" and the self-check is "troubleshooting", and on top of that
    /// the self-check is normally "everything is fine" — a tab that always states
    /// the obvious is not worth a slot.
    @Published private(set) var showsHealthCheck = false

    func showHealthCheck() { showsHealthCheck = true }
    func dismissHealthCheck() {
        showsHealthCheck = false
        // Dismissing the sheet counts as finishing the first-run guide, so it stops
        // appearing. Until then it comes back on every launch, which is what makes it
        // usable as an onboarding step rather than a one-shot notice.
        AppGroupStore.markFirstRunCompleted()
    }

    /// Stores the chosen language and makes the UI follow it at once: the strings are
    /// looked up while rendering, so nothing here needs a relaunch.
    func setLanguage(_ language: AppLanguage) {
        var updated = preferences
        updated.language = language
        preferences = updated
        // The lookup cache must be invalidated immediately, otherwise the UI can
        // take up to half a second to follow the change.
        LocalizedText.languageOverride = language
        LocalizedText.invalidate()
        do {
            try AppGroupStore.savePreferences(preferences)
        } catch {
            DiagnosticsLog.log("language preference not saved: \(error.localizedDescription)")
        }

    }

    func openExtensionSettings() {
        // Order matters and `open` reports success even when the pane only comes to the
        // front, so the first candidate is the one verified to land on Login Items &
        // Extensions. `com.apple.AppleFileProvider` was tried first and landed on
        // General on at least one system, where it also stopped the fallbacks from
        // being reached — so it is gone.
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        ]
        // System Settings, when already running, often just comes to the front and
        // keeps whatever page it was showing — which is why the destination looked
        // random (sometimes General, sometimes Login Items). Quitting it first makes
        // the URL actually navigate; it has no unsaved state to lose.
        quitSystemSettings()
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// Quits System Settings and waits for it to go, so the URL that follows is
    /// handled by a fresh launch rather than an existing window.
    private func quitSystemSettings() {
        let identifier = "com.apple.systempreferences"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        guard !running.isEmpty else { return }

        running.forEach { $0.terminate() }

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline,
              !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty {
            usleep(50_000)
        }
    }

    private let catalog = ScriptCatalogService.shared

    private init() {
        // Both the Accessibility toggle and the notification switch live in
        // System Settings, so re-read them whenever the user comes back.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshRenamePermission()
            self?.refreshNotificationAuthorization()
            self?.refreshLaunchAtLogin()
            // Picking a script up after dropping it in the folder means
            // rescanning, otherwise the list would look stale.
            self?.reload()
        }

        reload()
    }

    var userTemplatesDirectory: URL? {
        TemplateCatalogService.userTemplatesDirectory
    }

    var scriptsDirectory: URL {
        AppPaths.scriptsDirectory
    }

    func reload() {
        preferences = AppGroupStore.loadPreferences()
        LocalizedText.languageOverride = preferences.resolvedLanguage
        refreshFinderMenuState()
        refreshRenamePermission()
        refreshNotificationAuthorization()
        refreshLaunchAtLogin()

        do {
            let snapshot = try catalog.refresh()
            templates = TemplateCatalogService.orderedTemplates(preferences: preferences)
            scripts = snapshot.scripts
            statusMessage = nil
        } catch {
            // Fall back to a read-only view of the catalog so the window is
            // still usable when the App Group container is unavailable.
            templates = TemplateCatalogService.orderedTemplates(preferences: preferences)
            scripts = []
            report(error)
        }
    }

    // MARK: - Finder extension

    /// Reading the election state spawns `pluginkit`, so keep it off the main
    /// thread and publish the result back on it.
    func refreshFinderMenuState() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let state = FinderExtensionController.currentState()
            DispatchQueue.main.async {
                self?.finderMenuState = state
            }
        }
    }

    func setFinderMenuEnabled(_ isEnabled: Bool) {
        do {
            try FinderExtensionController.setEnabled(isEnabled)
            statusMessage = nil
        } catch {
            report(error)
        }

        refreshFinderMenuState()
    }

    // MARK: - New file rename

    func refreshRenamePermission() {
        canAutoRename = FinderRenameService.isPermitted
    }

    func requestRenamePermission() {
        FinderRenameService.requestPermission()
        // macOS sends the user to System Settings; re-check shortly after in
        // case they come straight back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.refreshRenamePermission()
        }
    }

    // MARK: - Launch at login

    func refreshLaunchAtLogin() {
        launchAtLogin = LaunchAtLoginService.state == .enabled
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(isEnabled)
            statusMessage = nil
        } catch {
            report(error)
        }

        refreshLaunchAtLogin()
    }

    // MARK: - Notifications

    func refreshNotificationAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let authorized = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional

            DispatchQueue.main.async {
                self?.notificationsAuthorized = authorized
            }
        }
    }

    // MARK: - Templates

    func isTemplateEnabled(_ template: FileTemplate) -> Bool {
        preferences.templates[template.id]?.isEnabled ?? true
    }

    func setTemplate(_ template: FileTemplate, enabled: Bool) {
        var preference = preferences.templates[template.id] ?? TemplatePreference()
        preference.isEnabled = enabled
        preferences.templates[template.id] = preference
        persist()
    }

    func revealTemplatesDirectory() {
        guard let directory = userTemplatesDirectory else {
            return
        }
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func requestNotificationAuthorization() {
        NotificationService.shared.requestAuthorization()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshNotificationAuthorization()
        }
    }

    // MARK: - Toolbox

    func isToolboxEnabled(_ id: ToolboxItemID) -> Bool {
        preferences.toolbox[id.rawValue]?.isEnabled ?? true
    }

    /// Applies a drag in the toolbox list. The whole list is re-numbered so the
    /// order stays stable when entries are added or removed later.
    func moveToolbox(from source: Int, to destination: Int) {
        var ordered = orderedToolbox
        guard ordered.indices.contains(source), ordered.indices.contains(destination) else {
            return
        }
        ordered.insert(ordered.remove(at: source), at: destination)

        for (position, item) in ordered.enumerated() {
            var preference = preferences.toolbox[item.id.rawValue] ?? ToolboxPreference()
            preference.order = (position + 1) * 10
            preferences.toolbox[item.id.rawValue] = preference
        }
        persist()
    }

    /// Applies a drag in the scripts list.
    func moveScripts(from source: Int, to destination: Int) {
        var ordered = scripts
        guard ordered.indices.contains(source), ordered.indices.contains(destination) else {
            return
        }
        ordered.insert(ordered.remove(at: source), at: destination)

        for (position, script) in ordered.enumerated() {
            var preference = preferences.scripts[script.id] ?? ScriptPreference()
            preference.order = (position + 1) * 10
            preferences.scripts[script.id] = preference
        }
        persist()
    }

    /// Applies a drag in the template list.
    func moveTemplates(from source: Int, to destination: Int) {
        var ordered = templates
        guard ordered.indices.contains(source), ordered.indices.contains(destination) else {
            return
        }
        ordered.insert(ordered.remove(at: source), at: destination)

        for (position, template) in ordered.enumerated() {
            var preference = preferences.templates[template.id] ?? TemplatePreference()
            preference.order = (position + 1) * 10
            preferences.templates[template.id] = preference
        }
        persist()
    }

    /// Toolbox entries in menu order, including disabled ones. Entries the
    /// chosen compressor cannot perform (7z with the built-in tools) are absent.
    var orderedToolbox: [ToolboxItem] {
        ToolboxCatalog.orderedItems(
            preferences: preferences.toolbox,
            creatableFormats: selectedCreatableFormats
        )
    }

    /// Formats the chosen compressor can produce.
    var selectedCreatableFormats: Set<String> {
        CompressionService.shared
            .compressor(for: preferences)
            .capabilities
            .createsFormats
    }

    func setToolbox(_ id: ToolboxItemID, enabled: Bool) {
        var preference = preferences.toolbox[id.rawValue] ?? ToolboxPreference()
        preference.isEnabled = enabled
        preferences.toolbox[id.rawValue] = preference
        persist()
    }

    // MARK: - Scripts

    func isScriptEnabled(_ script: ScriptPackage) -> Bool {
        preferences.scripts[script.id]?.isEnabled ?? true
    }

    func setScript(_ script: ScriptPackage, enabled: Bool) {
        var preference = preferences.scripts[script.id] ?? ScriptPreference()
        preference.isEnabled = enabled
        preferences.scripts[script.id] = preference
        persist()
    }

    func removeScript(_ script: ScriptPackage) throws {
        let root = AppPaths.scriptsDirectory
        let directory = root.appendingPathComponent(script.relativeDirectory, isDirectory: true)

        // Defensive: only ever delete something inside the scripts directory.
        guard directory.path != root.path,
              directory.path.hasPrefix(root.path + "/") else {
            throw ScriptCatalogError.scriptUnavailable(script.id)
        }

        try FileManager.default.removeItem(at: directory)
        preferences.scripts.removeValue(forKey: script.id)
        DiagnosticsLog.log("script removed: \(directory.path)")
        persist()
    }

    /// Puts every switch, order and choice back to its default.
    ///
    /// Files are deliberately left alone: the script packages, their generated
    /// icons and any user templates are the user's own content, and losing them to
    /// something labelled "reset" would be unforgivable.
    ///
    /// What is dropped is the record of which bundled scripts were offered, and the
    /// bundled scripts are offered again straight away. That is the one thing a
    /// factory reset should undo about scripts: one the user deleted on purpose — or
    /// by accident — comes back, while the packages still on disk and anything the
    /// user wrote themselves are left exactly as they are.
    func resetToDefaults() {
        preferences = AppPreferences()
        try? FileManager.default.removeItem(at: AppPaths.seededScriptsRecord)
        _ = BuiltinScriptSeeder.seedIfNeeded()
        // Forget that the first-run guide was shown, so it comes back. A reset that
        // left the guide suppressed meant a user could never see it again, and there
        // was no way to get it back short of deleting files by hand.
        try? FileManager.default.removeItem(at: AppGroupStore.firstRunMarker)
        DiagnosticsLog.log("preferences reset to defaults; bundled scripts and guide offered again")
        persist()
    }

    /// Whether the templates folder holds anything the user put there.
    ///
    /// The row is hidden while it is empty: it is an entry point for a feature
    /// the user may never use, and an empty folder behind it just raises the
    /// question of what it is for. Drop a template in and the row appears.
    var hasUserTemplates: Bool {
        guard let directory = userTemplatesDirectory else {
            return false
        }
        let contents = (try? FileManager.default.contentsOfDirectory(
            atPath: directory.path
        )) ?? []
        return contents.contains { !$0.hasPrefix(".") }
    }

    func revealScriptsDirectory() {
        let directory = scriptsDirectory
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    // MARK: - Compression

    func setCompressor(_ identifier: String?) {
        preferences.compressorIdentifier = identifier
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            try AppGroupStore.savePreferences(preferences)
            let snapshot = try catalog.refresh()
            templates = TemplateCatalogService.orderedTemplates(preferences: preferences)
            scripts = snapshot.scripts
            statusMessage = nil
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        NSLog("RightKit settings error: %@", error.localizedDescription)
        statusMessage = error.localizedDescription
    }

}
