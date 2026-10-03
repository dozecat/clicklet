import Foundation

/// Where "open in terminal" should land.
///
/// A selected folder is the place itself; a selected file means the folder holding it;
/// with nothing selected it is the folder the menu was opened in. Taking the parent
/// unconditionally is what put a right-clicked folder's terminal one level up, so this
/// is a pure function with tests rather than a branch inside the coordinator.
enum TerminalTarget {
    nonisolated static func directory(selectedPaths: [String], directoryPath: String) -> URL {
        guard let first = selectedPaths.first else {
            return URL(fileURLWithPath: directoryPath, isDirectory: true)
        }

        let url = URL(fileURLWithPath: first)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }
}
