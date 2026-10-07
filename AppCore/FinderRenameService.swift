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
///
/// Main-actor bound: every AppKit call here (`NSApp.hide`, `NSRunningApplication`)
/// and the `DispatchQueue.main.asyncAfter` poll loop are main-thread work, and this
/// makes that a compile-time fact rather than a convention.
@MainActor
enum FinderRenameService {
    private static let returnKeyCode: CGKeyCode = 36
    private static let finderBundleIdentifier = "com.apple.finder"

    /// How long `beginRename` may spend waiting before it gives up.
    ///
    /// A ceiling, not a delay: the normal path returns in about a third of a second and
    /// never approaches it, so the value only decides how long a stuck case makes the
    /// user wait before the file is simply left selected. The elapsed time is logged on
    /// both paths, so this can be tuned from real numbers.
    nonisolated private static let defaultTimeout: TimeInterval = 2.5

    /// How long to wait for Finder to finish applying the selection once its window is
    /// key. Much shorter than the old fixed delay, because that delay is now the only
    /// part still based on a guess rather than on observed state.
    private static let settleAfterKeyWindow: TimeInterval = 0.25

    /// Ceiling on a single Accessibility call. The framework's own default is six
    /// seconds, which is long enough to look like a hang; a busy Finder must not be able
    /// to stall the rename path for that long. Must stay well under `defaultTimeout`,
    /// since a poll can block for this long.
    private static let accessibilityMessagingTimeout: Float = 0.5

    /// How often to re-check while waiting.
    private static let pollInterval: TimeInterval = 0.08

    /// Identifies the current attempt. A second New File while one is still waiting —
    /// two fast menu picks, or a folder and a keystroke — would otherwise leave two poll
    /// loops running and post two Return keystrokes, which enters rename mode and then
    /// immediately commits it.
    private static var attempt = 0

    /// `nonisolated`: a pure Accessibility query, and callers in the settings layer
    /// read it from outside the main actor.
    nonisolated static var isPermitted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks macOS to show the "grant Accessibility access" prompt.
    nonisolated static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Polls until Finder is genuinely ready for the keystroke, then types Return.
    ///
    /// Waiting for "Finder is frontmost" was not enough, which is why this had a
    /// reputation for working only sometimes. That condition holds while Finder is still
    /// finishing the window it needs, and it is at its worst on a cold start — neither
    /// the extension nor Finder has run for a while, so the keystroke landed before
    /// there was a key window to receive it. The wait is now for the state that actually
    /// matters: Finder's focused window holding the item that was just created.
    ///
    /// Every stage shares one deadline and is logged with its elapsed time, so a rename
    /// that does not happen says where it stopped.
    static func beginRename(of url: URL, timeout: TimeInterval = defaultTimeout) {
        guard isPermitted else {
            DiagnosticsLog.log(
                "inline rename skipped for \(url.lastPathComponent): "
                    + "Accessibility permission not granted"
            )
            return
        }

        attempt += 1
        let thisAttempt = attempt
        let started = Date()
        let deadline = started.addingTimeInterval(timeout)
        waitForFinderToBeFrontmost(deadline: deadline, started: started, url: url, attempt: thisAttempt)
    }

    // MARK: - Waiting

    private static func waitForFinderToBeFrontmost(
        deadline: Date,
        started: Date,
        url: URL,
        attempt thisAttempt: Int
    ) {
        guard thisAttempt == attempt else { return }
        guard Date() < deadline else {
            logFailure("Finder never came to the front", started: started, url: url)
            return
        }

        // Step aside only if we have been in the way for a while. Hiding at once would
        // take an open settings window off screen, and the app is normally woken in the
        // background anyway, so this rarely fires.
        if NSApp.isActive, Date().timeIntervalSince(started) > 0.6 {
            DiagnosticsLog.log("inline rename: stepping aside for Finder")
            NSApp.hide(nil)
        }

        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            == finderBundleIdentifier else {
            retry {
                waitForFinderToBeFrontmost(deadline: deadline, started: started, url: url, attempt: thisAttempt)
            }
            return
        }

        waitForFinderToShowItem(deadline: deadline, started: started, url: url, attempt: thisAttempt)
    }

    /// Finder is frontmost; wait until its focused window is showing the new item.
    ///
    /// "Has a focused window" alone is not sufficient, and this was the remaining hole:
    /// Finder very often has a window open on some *other* folder, which satisfies it
    /// while the keystroke lands nowhere useful. Asking for the item in the selection is
    /// the same question the keystroke depends on.
    private static func waitForFinderToShowItem(
        deadline: Date,
        started: Date,
        url: URL,
        attempt thisAttempt: Int
    ) {
        guard thisAttempt == attempt else { return }
        guard Date() < deadline else {
            logFailure("Finder's focused window never held the new item", started: started, url: url)
            return
        }

        switch focusedWindowSelection(showing: url) {
        case .showsItem:
            break
        case .doesNotShowItem:
            retry {
                waitForFinderToShowItem(deadline: deadline, started: started, url: url, attempt: thisAttempt)
            }
            return
        case .unreadable:
            // Finder did not expose a selection we could read. Rather than burn the whole
            // deadline on a condition that may never become readable, accept a focused
            // window — the previous behaviour — and say so in the log.
            guard finderHasFocusedWindow() else {
                retry {
                    waitForFinderToShowItem(deadline: deadline, started: started, url: url, attempt: thisAttempt)
                }
                return
            }
            DiagnosticsLog.log("inline rename: selection unreadable, using focused window alone")
        }

        // The window is up and holds the item; give Finder a moment to finish applying the
        // selection. Clamped to what is left of the deadline, so the total wait cannot
        // exceed the budget the caller allowed.
        let settle = min(settleAfterKeyWindow, max(0, deadline.timeIntervalSinceNow))
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
            guard thisAttempt == attempt else { return }
            guard Date() < deadline else {
                logFailure("no time left to send the keystroke", started: started, url: url)
                return
            }

            postReturnKey()
            DiagnosticsLog.log(
                "inline rename requested for \(url.lastPathComponent) "
                    + "after \(elapsed(since: started))s"
            )
        }
    }

    /// Schedules the next poll.
    ///
    /// The closure is `@MainActor` as well as `@Sendable` because everything it calls
    /// touches AppKit. `assumeIsolated` is sound here — `asyncAfter` on `.main` runs on
    /// the main thread — and it is what carries that fact across the queue hop.
    private static func retry(_ work: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
            MainActor.assumeIsolated {
                work()
            }
        }
    }

    // MARK: - Reading Finder's state

    private enum SelectionReading {
        case showsItem
        case doesNotShowItem
        /// Finder did not expose the attributes needed to tell. Not an error: some
        /// windows, and some releases, simply do not report a selection this way.
        case unreadable
    }

    private static func focusedWindowSelection(showing url: URL) -> SelectionReading {
        guard let application = finderApplicationElement() else { return .unreadable }
        guard let window: AXUIElement = copyAttribute(application, kAXFocusedWindowAttribute) else {
            return .doesNotShowItem
        }
        guard let selected: [AXUIElement] = copyAttribute(window, kAXSelectedChildrenAttribute) else {
            return .unreadable
        }
        // Rows carry the file they stand for; anything unreadable just means this window
        // is not the one we are waiting for.
        return selected.contains { row in
            guard let itemURL: URL = copyAttribute(row, kAXURLAttribute) else { return false }
            return itemURL == url
        } ? .showsItem : .doesNotShowItem
    }

    private static func finderHasFocusedWindow() -> Bool {
        guard let application = finderApplicationElement() else { return false }
        let window: AXUIElement? = copyAttribute(application, kAXFocusedWindowAttribute)
        return window != nil
    }

    private static func finderApplicationElement() -> AXUIElement? {
        guard let finder = NSRunningApplication
            .runningApplications(withBundleIdentifier: finderBundleIdentifier)
            .first else {
            return nil
        }

        let application = AXUIElementCreateApplication(finder.processIdentifier)
        // Keeps an unresponsive Finder from blocking this process for the framework's
        // six-second default.
        AXUIElementSetMessagingTimeout(application, accessibilityMessagingTimeout)
        return application
    }

    private static func copyAttribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    // MARK: - Sending the keystroke

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

    // MARK: - Logging

    private static func logFailure(_ reason: String, started: Date, url: URL) {
        DiagnosticsLog.log(
            "inline rename gave up for \(url.lastPathComponent) "
                + "after \(elapsed(since: started))s: \(reason)"
        )
    }

    private static func elapsed(since started: Date) -> String {
        String(format: "%.2f", Date().timeIntervalSince(started))
    }
}
