import SwiftUI

struct GeneralView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Section("Features") {
                    Label("New File", systemImage: "doc.badge.plus")
                    Label("Scripts", systemImage: "terminal")
                    Label("Compression", systemImage: "archivebox")
                }
                Section("Other") {
                    Label("General", systemImage: "gearshape")
                    Label("About", systemImage: "info.circle")
                }
            }
        } detail: {
            Text("RightKit")
                .foregroundStyle(.secondary)
        }
    }
}
