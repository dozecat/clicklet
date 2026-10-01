import AppKit
import ApplicationServices

/// Starts Finder's inline rename on a freshly created item, the way Finder's own
/// "New Folder" command does.
///
/// Finder exposes no scripted or programmatic way to enter rename mode, so the
/// only route is to select the item in Finder and send it a Return keystroke.
/// Posting synthetic events into another application requires the Accessibility
/// permission; without it the file is still created and selected, the user just
/// has to press Return themselves.
enum FinderRenameService {
    private static let returnKeyCode: CGKeyCode = 36
    private static let finderBundleIdentifier = "com.apple.finder"

    /// Default delay before the keystroke: Finder needs a moment to come to the
    /// front and finish updating its selection.
    private static let defaultDelay: TimeInterval = 0.45

    static var isPermitted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks macOS to show the "grant Accessibility access" prompt.
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func beginRename(of url: URL, delay: TimeInterval = defaultDelay) {
        guard isPermitted else {
            DiagnosticsLog.log(
                "inline rename skipped for \(url.lastPathComponent): "
                    + "Accessibility permission not granted"
            )
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Never type into whatever happens to be frontmost: a stray Return
            // elsewhere could open a file.
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                == finderBundleIdentifier else {
                DiagnosticsLog.log("inline rename skipped: Finder is not frontmost")
                return
            }

            postReturnKey()
            DiagnosticsLog.log("inline rename requested for \(url.lastPathComponent)")
        }
    }

    private static func postReturnKey() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: returnKeyCode,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: returnKeyCode,
                keyDown: false
              ) else {
            return
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
