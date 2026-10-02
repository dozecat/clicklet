import AppKit
import Combine
import SwiftUI

/// Root of the settings window: a Safari-style tab strip above a single pane.
struct SettingsWindowView: View {
    @StateObject private var store = SettingsStore.shared
    @State private var selection: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabStrip(selection: $selection).id(store.preferences.resolvedLanguage)

            Divider()

            SettingsStatusBanner(message: store.statusMessage)

            pane
        }
        .frame(width: 700, height: 540)
        // Hands the one supported way of opening this scene back to AppKit
        // callers. Publishing on appear is enough: the Dock path is only
        // reachable once the app is running, and by then the menu item (which
        // works on its own) has opened this window at least once.
        .background(SettingsActionExporter())
        // SwiftUI ignores `.windowStyle(.hiddenTitleBar)` on a Settings scene, so
        // the title bar comes back with a title in it. The tab strip is meant to
        // be the title bar, so hide the text and let the content run up into it.
        .onAppear { hideWindowTitle() }
        // The self-check appears as a sheet: it pops up automatically on first run,
        // and afterwards is summoned from the Help menu.
        .sheet(
            isPresented: Binding(
                get: { store.showsHealthCheck },
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
            hideWindowTitle()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .environmentObject(store)
    }

    /// SwiftUI ignores `.windowStyle(.hiddenTitleBar)` on a `Settings` scene, so
    /// the title bar returns with a title in it. The tab strip is meant to be the
    /// title bar, so blank the text and let the content run up into that space.
    private func hideWindowTitle() {
        // No longer filtering on canBecomeMain: the settings window SwiftUI has just
        // created may not be main-capable yet at the moment onAppear runs, so it
        // would be missed entirely — which is very likely why the title kept coming
        // back.
        for window in NSApp.windows {
            window.title = ""
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
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
