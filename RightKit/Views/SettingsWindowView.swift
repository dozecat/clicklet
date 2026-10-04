import AppKit
import Combine
import SwiftUI

/// Root of the settings window: a Safari-style tab strip above a single pane.
struct SettingsWindowView: View {
    /// Kept alive because `NSToolbar.delegate` is weak.
    fileprivate static var titleToolbarDelegates: [TitleToolbarDelegate] = []
    @StateObject private var store = SettingsStore.shared
    @State private var selection: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabStrip(selection: $selection).id(store.preferences.resolvedLanguage)

            Divider()

            SettingsStatusBanner(message: store.statusMessage)

            pane
        }
        .frame(width: settingsWindowWidth, height: 520)
        // The strip must NOT run up into the toolbar: the centred name lives there, so
        // ignoring the top safe area put the two in the same band and they overlapped.
        // Below the toolbar is where 1Capture has it too.
        // Hands the one supported way of opening this scene back to AppKit
        // callers. Publishing on appear is enough: the Dock path is only
        // reachable once the app is running, and by then the menu item (which
        // works on its own) has opened this window at least once.
        .background(SettingsActionExporter())
        // SwiftUI ignores `.windowStyle(.hiddenTitleBar)` on a Settings scene, so
        // the title bar comes back with a title in it. The tab strip is meant to
        // be the title bar, so hide the text and let the content run up into it.
        .onAppear {
            configureWindow()

            // And again on the next run loop turn. On the first open SwiftUI finishes
            // configuring the title bar *after* onAppear, which puts the separator back
            // — that is why the rule was visible until the window was clicked, since
            // the didBecomeKey pass below only starts helping from the second key event.
            DispatchQueue.main.async { configureWindow() }
        }
        // The self-check appears as a sheet: it pops up automatically on first run,
        // and afterwards is summoned from the Help menu.
        .sheet(
            isPresented: Binding(
                get: { false },
                set: { if !$0 { store.dismissHealthCheck() } }
            )
        ) {
            SelfCheckSheet()
        }
        // SwiftUI may write the title back again later. Blank it once more every
        // time the window becomes key, so this does not depend on the assumption
        // that "at onAppear the window already exists and is main-capable".
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
        ) { _ in
            configureWindow()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .environmentObject(store)
    }

    /// SwiftUI ignores `.windowStyle(.hiddenTitleBar)` on a `Settings` scene, so
    /// the title bar returns with a title in it. The tab strip is meant to be the
    /// title bar, so blank the text and let the content run up into that space.
    /// Gives the window the 1Capture-style title bar: the name centred in the toolbar
    /// area, no rule under it, and the tab strip as the first row of the content.
    ///
    /// An empty `NSToolbar` is not enough — the title stays left-aligned. Centring it
    /// needs a toolbar item of our own plus `centeredItemIdentifier`, which is what
    /// this does.
    private func configureWindow() {
        let title = LocalizedText.string("设置", language: LocalizedText.currentLanguage)

        for window in NSApp.windows {
            window.title = title
            // The name is drawn by the toolbar item below, not by the title bar.
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarSeparatorStyle = .none

            // Only once: this runs again on every didBecomeKey.
            if window.toolbar == nil {
                let delegate = TitleToolbarDelegate(title: title)
                // The toolbar holds its delegate weakly, so keep ours alive.
                Self.titleToolbarDelegates.append(delegate)

                let toolbar = NSToolbar()
                toolbar.delegate = delegate
                toolbar.showsBaselineSeparator = false
                toolbar.displayMode = .iconOnly
                toolbar.centeredItemIdentifier = TitleToolbarDelegate.titleIdentifier

                window.toolbar = toolbar
                window.toolbarStyle = .unified
            }
        }
    }

    @ViewBuilder
    private var pane: some View {
        // Identity follows the language: SwiftUI only compares the Text keys, and
        // when the key has not changed it sees no reason to redraw, so the same key
        // with a different bundle does not trigger a refresh (it shows up as "you
        // have to click once before it changes").
        // The .id makes this branch rebuild as a whole when the language changes, and
        // the strings are then resolved again.
        switch selection {
        case .general:
            GeneralPane().id(store.preferences.resolvedLanguage)
        case .toolbox:
            ToolboxPane().id(store.preferences.resolvedLanguage)
        case .newFile:
            NewFilePane().id(store.preferences.resolvedLanguage)
        case .compression:
            CompressionPane().id(store.preferences.resolvedLanguage)
        case .scripts:
            ScriptsPane().id(store.preferences.resolvedLanguage)
        case .about:
            AboutPane().id(store.preferences.resolvedLanguage)
        }
    }
}

/// Supplies the single toolbar item that draws the window's name centred.
///
/// `NSToolbar.items` is read-only, and a custom identifier needs a delegate to supply
/// it. `centeredItemIdentifier` is what actually centres it — an empty toolbar leaves
/// the title left-aligned, which is why this exists at all.
private final class TitleToolbarDelegate: NSObject, NSToolbarDelegate {
    static let titleIdentifier = NSToolbarItem.Identifier("rightkit.title")

    private let title: String

    init(title: String) {
        self.title = title
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.alignment = .center
        label.sizeToFit()
        item.view = label
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.titleIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.titleIdentifier]
    }
}
