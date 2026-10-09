import Foundation

enum FinderActionKind: String, Codable {
    case newFile
    case runScript
    /// Opening Terminal is done by the main app: the extension is sandboxed and
    /// cannot hand an arbitrary directory to another application.
    case openInTerminal
    /// Toolbox archive commands that name their operation up front instead of
    /// letting the archive tool ask.
    case compressZip
    case compressSevenZip
    case decompressHere
    case decompressIntoFolder
}

struct FinderActionRequest: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: FinderActionKind
    let directoryPath: String
    let selectedPaths: [String]
    let templateID: String?
    let scriptID: String?
}

/// What a Finder menu item should do once the user picks it.
///
/// This is resolved **inside the extension process** from the clicked item's
/// title or tag: `NSMenuItem.representedObject` does not survive the trip from
/// the extension to Finder (it always arrives `nil`), so nothing may be attached
/// to the menu item itself. See `MenuCommandRegistry`.
struct FinderCommand: Equatable {
    let kind: FinderActionKind
    let identifier: String?

    init(kind: FinderActionKind, identifier: String? = nil) {
        self.kind = kind
        self.identifier = identifier
    }

    init(kind: FinderActionKind, templateID: String) {
        self.init(kind: kind, identifier: templateID)
    }

    init(kind: FinderActionKind, scriptID: String) {
        self.init(kind: kind, identifier: scriptID)
    }

    var templateID: String? {
        kind == .newFile ? identifier : nil
    }

    var scriptID: String? {
        kind == .runScript ? identifier : nil
    }
}

enum FinderActionURL {
    static let scheme = "clicklet"

    static func make(for requestID: UUID) -> URL? {
        URL(string: "\(scheme)://action/\(requestID.uuidString)")
    }

    static func requestID(from url: URL) -> UUID? {
        guard url.scheme == scheme,
              url.host == "action",
              let identifier = url.pathComponents.dropFirst().first else {
            return nil
        }

        return UUID(uuidString: identifier)
    }
}
