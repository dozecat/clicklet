import AppKit
import Combine
import SwiftUI

/// Root of the settings window: a Safari-style tab strip above a single pane.
struct SettingsWindowView: View {
    @StateObject private var store = SettingsStore.shared
    @State private var selection: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabStrip(selection: $selection)

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
        // SwiftUI 之后可能又把标题写回来。窗口每次成为 key 时再抹一遍，
        // 这样不依赖"onAppear 那一刻窗口已经存在且是 main-capable"这个假设。
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
        // 不再用 canBecomeMain 过滤：SwiftUI 刚建好的设置窗口在 onAppear 那一刻
        // 可能还不是 main-capable，会被整个漏掉——这很可能就是标题一直还在的原因。
        for window in NSApp.windows {
            window.title = ""
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    @ViewBuilder
    private var pane: some View {
        switch selection {
        case .general:
            GeneralPane()
        case .toolbox:
            ToolboxPane()
        case .newFile:
            NewFilePane()
        case .compression:
            CompressionPane()
        case .scripts:
            ScriptsPane()
        case .about:
            AboutPane()
        }
    }
}
