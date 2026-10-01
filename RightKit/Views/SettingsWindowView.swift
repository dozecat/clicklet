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
