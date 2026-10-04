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

    /// The size the guide is designed for. Kept here rather than inferred from the
    /// hosting controller, which does not report it until after the first layout.
    private static let contentSize = NSSize(width: 640, height: 486)

    private var window: NSWindow?
    private var activationObserver: NSObjectProtocol?

    func show() {
        let window = ensureWindow()
        NSApp.activate(ignoringOtherApps: true)
        // Deliberately NOT `.floating`: that pins the window above everything for as
        // long as it exists, and the user cannot get to anything else. The window keeps
        // the normal level and is simply brought forward at the two moments that
        // matter — here, and when the app becomes active again below.
        window.makeKeyAndOrderFront(nil)
        centre(window)
        observeActivation()

        // Centred twice more, on the next two run loop turns. NSHostingController
        // reports its size only once the SwiftUI content has laid out, so the frame
        // measured right after showing is usually not the final one — which is why
        // the window used to appear off-centre.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.centre(window)
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                self.centre(window)
            }
        }
    }

    /// SwiftUI caches text by key, so swapping the language bundle does not redraw it;
    /// `.id()` did not help either. Rebuilding the hosting controller is the one thing
    /// that reliably shows the new language on the first switch.
    func refresh() {
        window?.contentViewController = NSHostingController(rootView: makeView())
    }

    func close() {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = nil
        window?.close()
        window = nil
    }

    // MARK: - Private

    /// Coming back from System Settings is the moment the guide tends to end up behind
    /// something, so it is brought forward again whenever the app becomes active.
    private func observeActivation() {
        guard activationObserver == nil else { return }

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window, window.isVisible else { return }
                window.makeKeyAndOrderFront(nil)
            }
        }
    }


    /// Centres on the visible frame, so the window never lands under the menu bar or
    /// the Dock, and works on whichever display the window is actually on.
    private func centre(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size

        window.setFrameOrigin(NSPoint(
            x: visible.origin.x + (visible.width - size.width) / 2,
            y: visible.origin.y + (visible.height - size.height) / 2
        ))
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }

        // Size and style are given at construction. Replacing `styleMask` afterwards,
        // as this used to do, reconfigures the frame and undoes any centring.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "RightKit"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: makeView())
        window.setContentSize(Self.contentSize)

        self.window = window
        return window
    }

    private func makeView() -> OnboardingView {
        let store = SettingsStore.shared

        return OnboardingView(
            onOpenExtensionSettings: { store.openExtensionSettings() },
            onOpenAccessibilitySettings: openAccessibilitySettings,
            language: store.preferences.resolvedLanguage,
            onSelectLanguage: { [weak self] language in
                store.setLanguage(language)
                self?.refresh()
            },
            onFinish: { [weak self] in
                AppGroupStore.markFirstRunCompleted()
                self?.close()
            }
        )
    }

    /// Two schemes, because which one System Settings answers to has changed between
    /// macOS releases.
    private func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systemsettings:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]

        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
