import AppKit
import SwiftUI

struct CompressionPane: View {
    @EnvironmentObject private var store: SettingsStore

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
                                Text(compressor.displayName).tag(compressor.identifier)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    } else {
                        SettingsValue(text: "未安装")
                        if let url = downloadURL(for: selectedCompressor) {
                            Button("下载…") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
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
            get: {
                store.preferences.compressorIdentifier
                    ?? compressors.first(where: { $0.isInstalled })?.identifier
                    ?? ""
            },
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


/// 压缩格式列表。条目多的时候（Keka 可解压 11 种）整行会跨过分割线末端，
/// 所以默认只列前几个，需要时展开。
///
/// 展开后仍然把宽度限制在分割线之内，让它换行而不是横着捅出去。
struct FormatList: View {
    let formats: [String]

    @State private var expanded = false

    /// 折叠时列出的条数。5 条的文字加上「展开」按钮之后仍落在分割线之内。
    private let collapsedCount = 5

    private var isCollapsible: Bool { formats.count > collapsedCount }

    private var display: String {
        guard isCollapsible, !expanded else {
            return formats.joined(separator: "、")
        }
        return formats.prefix(collapsedCount).joined(separator: "、") + "…"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // 折叠时让值取自然宽度，按钮紧跟在后面（仍在分割线之内）。
            // 展开时才限制宽度——否则 11 种格式会横着捅出分割线。
            // 这里不能用 .infinity：那会把「展开」按钮推到最右边（682pt），
            // 反而跨过分割线。
            SettingsValue(text: display)
                .frame(
                    maxWidth: expanded ? settingsValueWidthWithinSeparator : nil,
                    alignment: .leading
                )

            if isCollapsible {
                Button(expanded ? "收起" : "展开") {
                    expanded.toggle()
                }
                .buttonStyle(.link)
            }
        }
    }
}
