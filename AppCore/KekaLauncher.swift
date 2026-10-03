import AppKit

/// Opens Keka, and tries to land on its settings.
///
/// Keka exposes no way to ask for its preferences: the only scripting commands in
/// Keka.sdef are compress, extract and send, and the only URL scheme it registers is
/// a bare `keka:`. So this falls back to the keyboard shortcut macOS apps use for
/// Settings, ⌘, after giving Keka a moment to come to the front.
///
/// If Keka does not answer to that shortcut the result is still just Keka opening,
/// which is what the button did before. Sending the key needs Accessibility
/// permission; without it the event is dropped and nothing else changes.
enum KekaLauncher {
    static func openSettings() async {
        guard let app = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: KekaAdapter().identifier
        ) else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: configuration)

        // Long enough for a cold launch to reach the foreground, short enough that the
        // key does not arrive after the user has started doing something else.
        try? await Task.sleep(nanoseconds: 900_000_000)
        pressComma()
    }

    private static func pressComma() {
        let comma: CGKeyCode = 43  // kVK_ANSI_Comma
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: comma, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: comma, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
