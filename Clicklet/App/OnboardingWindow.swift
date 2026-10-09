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
    private var levelTimer: Timer?

    func show() {
        let window = ensureWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        centre(window)
        // Floating, except while System Settings is in front.
        //
        // The rule the guide needs is not "always on top" nor "only while this app is
        // active". It is: on top of everything the user might be reading, but out of the
        // way while they are switching permissions on — and back on top the moment that
        // window closes. Watching activation cannot express that: this app is
        // LSUIElement, so closing System Settings hands the focus to whatever else was
        // open and this app is never activated at all.
        //
        // What the frontmost application actually is happens to be exactly the question,
        // so that is what gets polled.
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        startLevelPolling()

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
        // Deferred: the caller is a SwiftUI callback, and swapping the content view
        // controller straight away lands in the middle of AppKit's layout pass, which
        // logs "It's not legal to call -layoutSubtreeIfNeeded on a view which is
        // already being laid out". Letting the current pass finish avoids it.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }

            window.contentViewController = NSHostingController(rootView: self.makeView())

            // A new content view controller carries its own size, and the window adopts
            // it while keeping its origin — which is the bottom-left corner in AppKit, so
            // the top edge appears to jump. Pin the size and re-centre instead.
            window.setContentSize(Self.contentSize)
            self.centre(window)
        }
    }

    /// Keeps the guide floating above everything except System Settings.
    ///
    /// Polling rather than notifications: the transitions that matter here — System
    /// Settings opening and closing — do not all produce a notification this app
    /// receives, and the check is a bundle identifier comparison four times a second.
    private func startLevelPolling() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window, window.isVisible else { return }

                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let settingsIsFront = front == "com.apple.systempreferences"

                // `.normal` while the user is in System Settings so the guide cannot
                // cover the switches they came to use; `.floating` otherwise, so it
                // comes back on top by itself when that window closes.
                window.level = settingsIsFront ? .normal : .floating
            }
        }
    }

    func close() {
        levelTimer?.invalidate()
        levelTimer = nil
        window?.level = .normal
        window?.close()
        window = nil
    }

    // MARK: - Private




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
        window.identifier = .rightKitAuxiliaryWindow
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
