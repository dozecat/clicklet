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

    /// Polls until Finder is genuinely in front, then types Return.
    ///
    /// A single fixed delay does not work. This app is woken by the URL that
    /// carries the action, and macOS activates it for that URL — sometimes
    /// *after* the handler has already hidden the app — so it and Finder spend a
    /// moment contending for the front. Waiting for the state we actually need,
    /// instead of guessing at a delay, is what makes the rename land.
    static func beginRename(of url: URL, timeout: TimeInterval = 4) {
        guard isPermitted else {
            DiagnosticsLog.log(
                "inline rename skipped for \(url.lastPathComponent): "
                    + "Accessibility permission not granted"
            )
            return
        }

        let started = Date()
        waitForFinder(deadline: started.addingTimeInterval(timeout), started: started, url: url)
    }

    private static func waitForFinder(deadline: Date, started: Date, url: URL) {
        guard Date() < deadline else {
            DiagnosticsLog.log(
                "inline rename gave up for \(url.lastPathComponent): "
                    + "Finder never came to the front"
            )
            return
        }

        // Step aside only if we have been in the way for a while. Hiding at once
        // would take an open settings window off screen, and the app is normally
        // woken in the background anyway, so this rarely fires.
        if NSApp.isActive, Date().timeIntervalSince(started) > 0.6 {
            DiagnosticsLog.log("inline rename: stepping aside for Finder")
            NSApp.hide(nil)
        }

        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            == finderBundleIdentifier else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                waitForFinder(deadline: deadline, started: started, url: url)
            }
            return
        }

        // Finder is in front; let it finish applying the selection — and, in a folder
        // it has just opened, creating the window — before the keystroke lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
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

        // Posted to Finder's own process rather than into the session. A session-level
        // post goes to whatever AppKit thinks is frontmost, and Finder reports itself
        // frontmost before its window is actually key — which is how the keystroke was
        // getting dropped. On the Desktop it is worse: Finder has only just created the
        // window it needs.
        if let finder = NSRunningApplication
            .runningApplications(withBundleIdentifier: finderBundleIdentifier)
            .first {
            keyDown.postToPid(finder.processIdentifier)
            keyUp.postToPid(finder.processIdentifier)
        } else {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
