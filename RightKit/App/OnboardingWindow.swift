import AppKit
import SwiftUI

/// Hosts the first-run guide in its own window.
///
/// A window rather than a sheet: the guide is the first thing a new user sees, and it
/// is also reachable later from the Help menu, so it must not depend on the settings
/// window being open.
@MainActor
final class OnboardingWindow {
    static let shared = OnboardingWindow()

    private var window: NSWindow?

    func show() {
        let window = ensureWindow()
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // Deferred to the next run loop turn: adjusting the frame synchronously here
        // ran while the hosting view was still laying out.
        DispatchQueue.main.async {
            guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            ))
        }
    }

    /// SwiftUI caches text by key, so swapping the language bundle does not redraw it;
    /// `.id()` did not help either. Rebuilding the hosting controller is the one thing
    /// that reliably shows the new language on the first switch.
    func refresh() {
        window?.contentViewController = NSHostingController(rootView: makeView())
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }

        let window = NSWindow(contentViewController: NSHostingController(rootView: makeView()))
        window.title = "RightKit"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.window = window
        return window
    }

    private func makeView() -> OnboardingView {
        let store = SettingsStore.shared
        return OnboardingView(
            extensionEnabled: store.finderMenuState == .enabled,
            accessibilityGranted: AXIsProcessTrusted(),
            onOpenExtensionSettings: { store.openExtensionSettings() },
            onOpenAccessibilitySettings: {
                // Two schemes, because which one System Settings answers to has
                // changed between releases.
                let candidates = [
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                    "x-apple.systemsettings:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
                ]
                for candidate in candidates {
                    if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                        return
                    }
                }
            },
            language: store.preferences.resolvedLanguage,
            onSelectLanguage: { [weak self] language in
                store.setLanguage(language)
                self?.refresh()
            },
            onFinish: { [weak self] in
                AppGroupStore.markFirstRunCompleted()
                self?.close()
            },
            onEnableExtension: {
                FinderExtensionController.forceReload()
            }
        )
    }

    func close() {
        window?.close()
        window = nil
    }
}
