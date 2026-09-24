import Foundation

enum NewFileService {
    static func uniqueURL(for name: String, in directory: URL) -> URL {
        directory.appendingPathComponent(name)
    }
}

enum ScriptScanner {
    static func scan() -> [URL] {
        []
    }
}

protocol CompressorAdapter {
    var name: String { get }
    var isInstalled: Bool { get }
}
