import AppKit
import SwiftUI

/// Script packages as a striped table: `图标 · 脚本名称 · 路径 · 启用`,
/// with `−` / `+` on the right of the column header to remove or import one.
///
/// The scripts directory stays the source of truth: importing copies a `.sh` in
/// and writes a minimal `config.json`, removing deletes the package folder.
struct ScriptsPane: View {
    @EnvironmentObject private var store: SettingsStore
    @State private var selection: ScriptPackage.ID?
    @State private var scriptPendingRemoval: ScriptPackage?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            if store.scripts.isEmpty {
                SettingsEmptyState(
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    title: "还没有脚本",
                    message: "把脚本包文件夹放进脚本目录即可出现在这里；每个包需要可执行的 script.sh。",
                    actionTitle: "打开脚本目录",
                    action: { store.revealScriptsDirectory() }
                )
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded { store.revealScriptsDirectory() }
                )
            } else {
                ReorderableRows(
                    items: store.scripts,
                    onMove: { from, to in store.moveScripts(from: from, to: to) },
                    stripe: { SettingsStripe(index: $0) },
                    isSelected: { $0.id == selection },
                    footer: { addRemoveRow }
                ) { script, _ in
                    row(for: script)
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded { reveal(script) }
                        )
                        .onTapGesture { selection = script.id }
                }
            }
        }
        .onDeleteCommand {
            if let script = selectedScript {
                scriptPendingRemoval = script
            }
        }
        .alert(
            "RightKit",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            presenting: errorMessage
        ) { _ in
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .confirmationDialog(
            "删除这个脚本？",
            isPresented: Binding(
                get: { scriptPendingRemoval != nil },
                set: { if !$0 { scriptPendingRemoval = nil } }
            ),
            presenting: scriptPendingRemoval
        ) { script in
            Button("删除「\(script.name)」", role: .destructive) {
                remove(script)
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("整个脚本包文件夹会从脚本目录中删除，无法撤销。")
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("图标")
                .frame(width: 52, alignment: .leading)
            Text("脚本名称")
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("双击一行可在 Finder 中打开该脚本的文件夹")
            Text("路径")
                .frame(width: 170, alignment: .leading)
            Text("启用")
                // Sits directly above the checkboxes rather than above their
                // column, which the control insets to the left.
                .padding(.leading, settingsCheckboxHeaderNudge)
                .frame(width: 52, alignment: .leading)

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

    /// Trailing row of the list: the add/remove pair sits right after the last
    /// entry and lines up with the 启用 column, so it reads as the end of the
    /// list rather than window chrome.
    private var addRemoveRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 2) {
                Button {
                    store.revealScriptsDirectory()
                } label: {
                    Image(systemName: "plus")
                }
                .help("打开脚本目录，把脚本包放进去（双击某一行则打开该脚本自己的文件夹）")

                Button {
                    if let script = selectedScript {
                        scriptPendingRemoval = script
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedScript == nil)
                .help("删除选中的脚本")
            }
            .buttonStyle(.borderless)
            // Same width as the 启用 column, so the two line up.
            .frame(width: 52, alignment: .leading)
        }
        .padding(.trailing, 30)
        .padding(.vertical, 7)
    }

    private func row(for script: ScriptPackage) -> some View {
        let isEnabled = store.isScriptEnabled(script)

        return HStack(spacing: 0) {
            icon(for: script)
                .frame(width: 52, alignment: .leading)

            Text(script.name)
                .opacity(isEnabled ? 1 : 0.5)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(script.relativeDirectory)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 170, alignment: .leading)
                .help(scriptsPath(for: script))

            Toggle(
                "",
                isOn: Binding(
                    get: { isEnabled },
                    set: { store.setScript(script, enabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .frame(width: 52, alignment: .leading)

            Spacer(minLength: 12)
        }
        .padding(.leading, settingsTableLeadingInset)
        .padding(.trailing, 18)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            Button("在 Finder 中显示") { reveal(script) }
            Divider()
            Button("删除脚本…", role: .destructive) { scriptPendingRemoval = script }
        }
    }

    /// A script may ship its own `icon.png`, or name an application to borrow
    /// the icon from; otherwise a symbol stands in.
    @ViewBuilder
    private func icon(for script: ScriptPackage) -> some View {
        if let path = script.iconPath, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
        } else if let identifier = script.applicationBundleIdentifier,
                  let image = SystemIcon.application(bundleIdentifier: identifier) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
        }
    }

    private var selectedScript: ScriptPackage? {
        guard let selection else {
            return nil
        }
        return store.scripts.first { $0.id == selection }
    }

    private func scriptsPath(for script: ScriptPackage) -> String {
        AppPaths.scriptsDirectory
            .appendingPathComponent(script.relativeDirectory, isDirectory: true)
            .path
    }

    private func reveal(_ script: ScriptPackage) {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: scriptsPath(for: script))
        ])
    }

    private func remove(_ script: ScriptPackage) {
        do {
            try store.removeScript(script)
            selection = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
