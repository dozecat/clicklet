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
        .background(Color(nsColor: .windowBackgroundColor))
        .environmentObject(store)
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
        }
    }
}
