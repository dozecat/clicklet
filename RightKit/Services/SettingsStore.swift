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

    /// 自检以 sheet 形式出现，不占页签：设置是"配置"，自检是"排查"，
    /// 而且自检的常态是"一切正常"——一个永远说废话的页签不值得占位置。
    @Published private(set) var showsHealthCheck = false

    func showHealthCheck() { showsHealthCheck = true }
    func dismissHealthCheck() { showsHealthCheck = false }

    /// 打开「登录项与扩展」的系统设置页。Ventura 之后扩展搬到了这里，
    /// 旧的面板标识留作回退。通用页与自检页共用。
    /// 会调用 MainActor 隔离的重启，所以整个方法标上。
    @MainActor
    func setLanguage(_ language: AppLanguage) {
        let previous = preferences.resolvedLanguage
        var updated = preferences
        updated.language = language
        preferences = updated
        do {
            try AppGroupStore.savePreferences(preferences)
        } catch {
            DiagnosticsLog.log("language preference not saved: \(error.localizedDescription)")
        }

        // 语言只有在**进程启动时**才会被 SwiftUI 读进去，所以光写偏好不够：
        // 之前只有启动时才写 AppleLanguages，于是选完不重启，值还停在旧语言。
        // 这里当场写，然后自动重开一次——用户要的是"自动变"，不是手动重启按钮。
        guard language != previous else { return }
        AppLanguage.applyToProcess(language)
        AppLanguage.relaunchApp()
    }

    func openExtensionSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
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
    /// icons and any user templates are the user's own content, and losing them
    /// to something labelled "reset" would be unforgivable. The built-in script
    /// record is kept too, so a package the user deleted is not resurrected.
    func resetToDefaults() {
        preferences = AppPreferences()
        DiagnosticsLog.log("preferences reset to defaults")
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
