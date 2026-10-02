import SwiftUI

/// The templates offered by Finder's "新建文件" submenu, as a striped table:
/// `图标 · 文件名 · 启用`, reordered by dragging a row.
///
/// The list shows **every** template including the switched-off ones, so a
/// template can always be switched back on. Templates come from the built-in
/// catalog plus whatever sits in the templates folder; there is no in-app
/// add/remove, so that folder stays the single source of truth. 「通用」页有
/// 「模板目录：显示」可以跳到它。
struct NewFilePane: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            header

            ReorderableRows(
                items: store.templates,
                onMove: { from, to in store.moveTemplates(from: from, to: to) },
                stripe: { SettingsStripe(index: $0) },
                footer: { EmptyView() }
            ) { template, _ in
                row(for: template)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("图标")
                .frame(width: 52, alignment: .leading)
            Text("文件名")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("启用")
                // Sits directly above the checkboxes rather than above their
                // column, which the control insets to the left.
                .padding(.leading, settingsCheckboxHeaderNudge)
                .frame(width: 52, alignment: .leading)

            // Matches the row below. Without it the 启用 column sits 12pt
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

    private func row(for template: FileTemplate) -> some View {
        let isEnabled = store.isTemplateEnabled(template)

        return HStack(spacing: 0) {
            // The icon Finder itself would show, so Word/Excel/PowerPoint keep
            // their own artwork instead of a stand-in symbol.
            Image(nsImage: SystemIcon.file(for: template))
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .frame(width: 52, alignment: .leading)
                .opacity(isEnabled ? 1 : 0.45)

            Text(template.name)
                .opacity(isEnabled ? 1 : 0.5)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(
                "",
                isOn: Binding(
                    get: { isEnabled },
                    set: { store.setTemplate(template, enabled: $0) }
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
        .help("\(template.name)（.\(template.fileExtension)）")
    }
}
