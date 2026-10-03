import SwiftUI

/// Basic right-click actions as a striped table:
/// `Icon · Display Name · Enabled`, reordered by dragging a row.
///
/// Everything here is real: the checkboxes and the order are written to the App
/// Group and republished in the menu snapshot, so the Finder menu — order
/// included — follows immediately.
struct ToolboxPane: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            header

            ReorderableRows(
                items: store.orderedToolbox,
                onMove: { from, to in store.moveToolbox(from: from, to: to) },
                stripe: { SettingsStripe(index: $0) },
                footer: { EmptyView() }
            ) { item, _ in
                row(for: item)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            L.t("图标")
                .frame(width: 52, alignment: .leading)
            L.t("显示名称")
                .frame(maxWidth: .infinity, alignment: .leading)
            L.t("启用")
                // Sits directly above the checkboxes rather than above their
                // column, which the control insets to the left.
                .padding(.leading, settingsCheckboxHeaderNudge)
                .frame(width: 52, alignment: .leading)

            // Matches the row below. Without it the Enabled column sits 12pt
            // further right here than on the scripts tab.
            Spacer(minLength: 12)
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(.leading, settingsTableLeadingInset)
        .padding(.trailing, 18)
        .padding(.top, 18)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func row(for item: ToolboxItem) -> some View {
        let isEnabled = store.isToolboxEnabled(item.id)

        return HStack(spacing: 0) {
            icon(for: item)
                .frame(width: 52, alignment: .leading)

            // item.title is a runtime String, which Text would treat as verbatim, so
            // it has to be turned into a key explicitly.
            Text(LocalizedStringKey(item.title))
                .opacity(isEnabled ? 1 : 0.5)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(
                "",
                isOn: Binding(
                    get: { isEnabled },
                    set: { store.setToolbox(item.id, enabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .frame(width: 52, alignment: .leading)

            // Keeps the checkbox off the card edge, and keeps this column in the
            // same place as on the scripts tab.
            Spacer(minLength: 12)
        }
        .padding(.leading, settingsTableLeadingInset)
        .padding(.trailing, 18)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .help(helpText(for: item))
    }

    /// Archive entries borrow the chosen compressor's icon; Terminal borrows
    /// Terminal's; the rest use a symbol.
    @ViewBuilder
    private func icon(for item: ToolboxItem) -> some View {
        if let bundleIdentifier = applicationBundleIdentifier(for: item),
           let image = SystemIcon.application(bundleIdentifier: bundleIdentifier) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: item.icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
        }
    }

    private func applicationBundleIdentifier(for item: ToolboxItem) -> String? {
        if item.id.usesCompressorIcon {
            // Same resolution the settings window and the actions use, so the icon can
            // never disagree with the compressor actually in force.
            return CompressionService.shared.compressor(for: store.preferences).identifier
        }

        if item.id == .openInTerminal {
            return ToolboxCatalog.terminalBundleIdentifier
        }

        return nil
    }

    private func helpText(for item: ToolboxItem) -> String {
        guard let backgroundTitle = item.backgroundTitle else {
            return item.title
        }
        return "\(item.title)；在空白处右键时显示为「\(backgroundTitle)」"
    }
}
