import AppKit
import UniformTypeIdentifiers

/// Real macOS icons, so lists show what the user already sees in Finder instead
/// of a look-alike symbol.
enum SystemIcon {
    /// The icon Finder would show for this template: the icon of the template
    /// file itself when it exists, otherwise the icon macOS uses for that file
    /// type — which is Word/Excel/PowerPoint's own icon once Office is installed.
    static func file(for template: FileTemplate) -> NSImage {
        if template.isUserTemplate, let path = template.contentPath {
            return NSWorkspace.shared.icon(forFile: path)
        }

        if let type = UTType(filenameExtension: template.fileExtension) {
            return NSWorkspace.shared.icon(for: type)
        }

        return NSWorkspace.shared.icon(for: .data)
    }

    /// The installed application's own icon.
    static func application(bundleIdentifier: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
