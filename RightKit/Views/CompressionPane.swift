import AppKit
import SwiftUI

struct CompressionPane: View {
    @EnvironmentObject private var store: SettingsStore

    @State private var kekaPermission: KekaPermission.State = .unknown

    private var compressors: [CompressorAdapter] {
        CompressionService.shared.availableCompressors
    }

    var body: some View {
        SettingsPane {
            SettingsRow("压缩软件") {
                HStack(spacing: 8) {
                    compressorIcon

                    if selectedCompressor.isInstalled {
                        Picker("", selection: selection) {
                            ForEach(Array(compressors.enumerated()), id: \.offset) { _, compressor in
                                // The built-in tools' name is a catalogue key; the
                                // other adapter's name is a product name and passes
                                // through the failed lookup unchanged.
                                L.t(compressor.displayName).tag(compressor.identifier)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    } else {
                        SettingsValue(text: "未安装")
                        if let url = downloadURL(for: selectedCompressor) {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: { L.t("下载…") }
                        }
                    }
                }
            }

            if selectedCompressor.identifier == KekaAdapter().identifier {
                SettingsRow("Keka 权限") { kekaPermissionRow }
            }

            SettingsGroupSeparator()

            SettingsRow("说明") {
                SettingsValue(
                    text: selectedCompressor.identifier == KekaAdapter().identifier
                        ? "Keka 支持 7z 与 zip；解压仍走系统工具。"
                        : "系统自带工具只压缩为 zip；想要 7z 请选 Keka。"
                )
            }

            SettingsGroupSeparator()

            SettingsRow("可压缩格式") {
                FormatList(formats: selectedCompressor.capabilities.createsFormats.sorted())
            }

            SettingsRow("可解压格式") {
                FormatList(formats: selectedCompressor.capabilities.archiveFormats.sorted())
            }
        }
    }

    private func refreshKekaPermission() async {
        kekaPermission = .unknown
        kekaPermission = await KekaPermission.check()
    }

    /// Keka is sandboxed and its CLI only reaches locations the user has allowed, so
    /// without the home-folder permission every 7z action from the menu fails. Showing
    /// the state is better than letting the user run into that error.
    @ViewBuilder
    private var kekaPermissionRow: some View {
        HStack(spacing: 8) {
            switch kekaPermission {
            case .granted:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                SettingsValue(text: "已就绪")
            case .missing:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                SettingsValue(text: "需要在 Keka 里开启「文件访问权限 → 启用主文件夹访问权限」")
                Button {
                    Task { await KekaLauncher.openSettings() }
                } label: { L.t("打开 Keka 设置") }
            case .notInstalled:
                SettingsValue(text: "未安装")
            case .unknown:
                SettingsValue(text: "检查中…")
            }
        }
        .onAppear { Task { await refreshKekaPermission() } }
        .onChange(of: selectedCompressor.identifier) { _ in
            Task { await refreshKekaPermission() }
        }
        // Coming back from Keka, where the setting lives, is the flow this is for.
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await refreshKekaPermission() }
        }
    }

    @ViewBuilder
    private var compressorIcon: some View {
        if let icon = SystemIcon.application(
            bundleIdentifier: selectedCompressor.identifier
        ) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
        }
    }

    private var selectedCompressor: CompressorAdapter {
        CompressionService.shared.compressor(for: store.preferences)
    }

    private var selection: Binding<String> {
        Binding(
            // Resolved through the service, exactly as the icon above is. Repeating the
            // fallback here is how the picker came to show Keka while the icon showed
            // the system tools: after a factory reset the preference is nil, and this
            // used to fall back to "first installed", which is Keka.
            get: { CompressionService.shared.compressor(for: store.preferences).identifier },
            set: { store.setCompressor($0) }
        )
    }

    private func downloadURL(for compressor: CompressorAdapter) -> URL? {
        guard compressor.identifier == KekaAdapter().identifier else {
            return nil
        }

        return URL(string: "https://www.keka.io")
    }
}


/// The list of compression formats.
///
/// With many entries (Keka can decompress 11 of them) the whole row runs past the
/// end of the separator, so the width is capped inside the separator and the text
/// is left to wrap — rather than collapsing the list, and rather than widening the
/// separator.
/// The formats as small capsules rather than a comma-separated run. With sixteen
/// extractable formats the sentence could not be counted at a glance; chips can.
struct FormatList: View {
    let formats: [String]

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(formats, id: \.self) { format in
                Text(format)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
        }
    }
}

/// Wraps its children onto as many lines as they need. `LazyVGrid` needs a fixed
/// column count, and a fixed `HStack` cannot wrap at all.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: totalHeight + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
