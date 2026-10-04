import AppKit
import SwiftUI

/// Hosts the self-check in a window of its own.
///
/// It used to be a sheet on the settings window, which meant summoning it also had to
/// open — and raise — the whole settings window. Troubleshooting should not require
/// that.
@MainActor
final class SelfCheckWindow {
    static let shared = SelfCheckWindow()

    private var window: NSWindow?

    func show() {
        let store = SettingsStore.shared
        let window = ensureWindow(store: store)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.centre(window)
        }
    }

    func close() {
        window?.close()
        window = nil
    }

    // MARK: - Private

    private func ensureWindow(store: SettingsStore) -> NSWindow {
        if let window { return window }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "RightKit"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: SelfCheckSheet().environmentObject(store)
        )
        window.setContentSize(NSSize(width: 620, height: 520))
        self.window = window
        return window
    }

    /// Centred on the visible frame once the SwiftUI content has laid out, for the same
    /// reason as the onboarding window: the hosting controller reports its size late.
    private func centre(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size

        window.setFrameOrigin(NSPoint(
            x: visible.origin.x + (visible.width - size.width) / 2,
            y: visible.origin.y + (visible.height - size.height) / 2
        ))
    }
}
