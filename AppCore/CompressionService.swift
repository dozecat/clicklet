import AppKit
import Foundation

enum CompressionError: LocalizedError {
    case unsupportedSelection
    case compressorUnavailable
    case unsupportedOperation
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSelection:
            return "The selected items are not supported for this operation."
        case .compressorUnavailable:
            return "Keka is not installed."
        case .unsupportedOperation:
            return "The selected compressor does not support this operation."
        case let .launchFailed(message):
            return "Unable to open Keka: \(message)"
        }
    }
}

struct CompressorCapabilities {
    /// Formats that can be created. Narrower than what can be read: rar can be
    /// unpacked but never written, and the built-in tools cannot make 7z.
    let createsFormats: Set<String>
    /// Formats that can be unpacked, including read-only ones such as rar.
    let archiveFormats: Set<String>
    let supportsDecompression: Bool
    let supportsPassword: Bool
    let usesNativeProgressUI: Bool

    /// macOS ships no 7-Zip, so this separates the built-in tools from Keka.
    var supportsSevenZip: Bool {
        createsFormats.contains("7z")
    }
}

protocol CompressorAdapter {
    var identifier: String { get }
    var displayName: String { get }
    var isInstalled: Bool { get }
    var capabilities: CompressorCapabilities { get }

    func perform(operation: CompressionOperation, urls: [URL]) async throws
}

/// macOS's own archive tools (`ditto`, `zip`, `tar`), used when nothing else is
/// installed or chosen. It cannot make 7z or rar archives, and the settings
/// window and toolbox follow that capability.
struct SystemArchiveAdapter: CompressorAdapter {
    /// Archive Utility's identifier: borrowing it gives the settings window the
    /// icon macOS itself uses for archives.
    let identifier = "com.apple.archiveutility"
    let displayName = "系统自带"

    var isInstalled: Bool {
        true
    }

    var capabilities: CompressorCapabilities {
        CompressorCapabilities(
            createsFormats: ["zip"],
            archiveFormats: ["zip", "tar", "gz", "bz2", "xz", "tgz", "tbz2"],
            supportsDecompression: true,
            supportsPassword: false,
            usesNativeProgressUI: false
        )
    }

    /// Archive work is done by `ArchiveService` with the system command-line
    /// tools; there is no application to hand anything to.
    func perform(operation: CompressionOperation, urls: [URL]) async throws {
        throw CompressionError.unsupportedOperation
    }
}

struct KekaAdapter: CompressorAdapter {
    let identifier = "com.aone.keka"
    let displayName = "Keka"

    var isInstalled: Bool {
        applicationURL != nil
    }

    var capabilities: CompressorCapabilities {
        CompressorCapabilities(
            // Keka can write zip and 7z through its command line; the rest of
            // the list is read-only support.
            createsFormats: ["zip", "7z"],
            archiveFormats: CompressionSupport.archiveExtensions,
            supportsDecompression: true,
            supportsPassword: true,
            usesNativeProgressUI: true
        )
    }

    func perform(operation: CompressionOperation, urls: [URL]) async throws {
        guard isInstalled else {
            throw CompressionError.compressorUnavailable
        }
        guard operation == .compress || capabilities.supportsDecompression else {
            throw CompressionError.unsupportedOperation
        }
        guard let applicationURL else {
            throw CompressionError.compressorUnavailable
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(
                urls,
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(
                        throwing: CompressionError.launchFailed(error.localizedDescription)
                    )
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    }
}

final class CompressionService {
    static let shared = CompressionService()

    private let adapters: [CompressorAdapter]

    private init() {
        adapters = [KekaAdapter(), SystemArchiveAdapter()]
    }

    /// Compressors the settings window can list and let the user pick.
    var availableCompressors: [CompressorAdapter] {
        adapters
    }

    /// The compressor in force: the user's choice, else the first installed one.
    var selectedCompressor: CompressorAdapter {
        compressor(for: AppGroupStore.loadPreferences())
    }

    /// Resolves the choice against a specific preferences value, so callers that
    /// hold unsaved state see the same answer this service would.
    func compressor(for preferences: AppPreferences) -> CompressorAdapter {
        adapters.first { $0.identifier == preferences.compressorIdentifier }
            ?? adapters.first { $0.isInstalled }
            ?? adapters[0]
    }

    func canDecompress(_ urls: [URL]) -> Bool {
        CompressionSupport.canDecompress(urls)
    }

    func perform(operation: CompressionOperation, urls: [URL]) async throws {
        guard !urls.isEmpty else {
            throw CompressionError.unsupportedSelection
        }
        if operation == .decompress, !canDecompress(urls) {
            throw CompressionError.unsupportedSelection
        }

        let preferredIdentifier = AppGroupStore.loadPreferences().compressorIdentifier
        guard let adapter = adapters.first(where: {
            $0.identifier == preferredIdentifier
        }) ?? adapters.first(where: \.isInstalled) else {
            throw CompressionError.compressorUnavailable
        }

        try await adapter.perform(operation: operation, urls: urls)
    }
}
