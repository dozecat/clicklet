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
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: { L.t("下载…") }
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


/// The list of compression formats.
///
/// With many entries (Keka can decompress 11 of them) the whole row runs past the
/// end of the separator, so the width is capped inside the separator and the text
/// is left to wrap — rather than collapsing the list, and rather than widening the
/// separator.
struct FormatList: View {
    let formats: [String]

    var body: some View {
        SettingsValue(text: formats.joined(separator: "、"))
            .frame(maxWidth: settingsValueWidthWithinSeparator, alignment: .leading)
    }
}
