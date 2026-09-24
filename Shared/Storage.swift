import Foundation

enum AppGroup {
    static let identifier = "group.com.dozecat.RightKit"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

enum AppPaths {
    static var scriptsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RightKit/Scripts", isDirectory: true)
    }

    static var logsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/RightKit", isDirectory: true)
    }
}
