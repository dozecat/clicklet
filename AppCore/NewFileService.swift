import Foundation

enum NewFileError: LocalizedError {
    case invalidName
    case directoryUnavailable(String)
    case missingBundledTemplate(String)
    case missingUserTemplate(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "The file name is invalid."
        case let .directoryUnavailable(path):
            return "The target folder is no longer available: \(path)"
        case let .missingBundledTemplate(name):
            return "The bundled starter document is missing from the app: \(name)"
        case let .missingUserTemplate(name):
            return "The template file is missing: \(name)"
        }
    }
}

enum NewFileService {
    /// Base name used when a template is picked, mirroring Finder's own
    /// "untitled folder" behaviour (and its Chinese counterpart): the item is
    /// created right away and the user renames it in place.
    static func defaultBaseName(
        preferredLanguage: String? = Locale.preferredLanguages.first
    ) -> String {
        (preferredLanguage?.hasPrefix("zh") ?? false) ? "新建文件" : "Untitled"
    }

    static func defaultFileName(
        for template: FileTemplate,
        preferredLanguage: String? = Locale.preferredLanguages.first
    ) -> String {
        let baseName = defaultBaseName(preferredLanguage: preferredLanguage)
        guard !template.fileExtension.isEmpty else {
            return baseName
        }
        return "\(baseName).\(template.fileExtension)"
    }

    static func uniqueURL(
        for name: String,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedURL = directory.appendingPathComponent(trimmedName)
        guard fileManager.fileExists(atPath: requestedURL.path) else {
            return requestedURL
        }

        let fileExtension = requestedURL.pathExtension
        let baseName = requestedURL.deletingPathExtension().lastPathComponent
        var index = 2

        while true {
            let candidateName: String
            if fileExtension.isEmpty {
                candidateName = "\(baseName) \(index)"
            } else {
                candidateName = "\(baseName) \(index).\(fileExtension)"
            }

            let candidateURL = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    /// Appends the template's extension when the user typed a bare name, so that
    /// "notes" becomes "notes.txt" instead of an extension-less file.
    static func resolvedFileName(for name: String, template: FileTemplate) -> String {
        guard !template.fileExtension.isEmpty,
              (name as NSString).pathExtension.isEmpty else {
            return name
        }

        return "\(name).\(template.fileExtension)"
    }

    /// Resolves a starter document inside the app bundle. The folder reference is
    /// the expected layout; the flat lookup keeps creation working if the project
    /// is ever regenerated without it.
    static func bundledResourceURL(named name: String) -> URL? {
        Bundle.main.url(
            forResource: name,
            withExtension: nil,
            subdirectory: BuiltinTemplates.bundledDirectoryName
        ) ?? Bundle.main.url(forResource: name, withExtension: nil)
    }

    @discardableResult
    static func createFile(
        from template: FileTemplate,
        named name: String,
        in directory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !trimmedName.contains("/"),
              trimmedName != ".",
              trimmedName != ".." else {
            throw NewFileError.invalidName
        }

        let fileName = resolvedFileName(for: trimmedName, template: template)
        let destinationURL = uniqueURL(for: fileName, in: directory, fileManager: fileManager)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw NewFileError.directoryUnavailable(directory.path)
        }

        switch template.contentSource {
        case .emptyText:
            try Data().write(to: destinationURL, options: .atomic)
        case .bundledResource:
            guard let resourceName = template.contentPath,
                  let sourceURL = bundledResourceURL(named: resourceName) else {
                throw NewFileError.missingBundledTemplate(template.contentPath ?? template.id)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        case .userFile:
            guard let path = template.contentPath else {
                throw NewFileError.missingUserTemplate(template.name)
            }
            let sourceURL = URL(fileURLWithPath: path)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw NewFileError.missingUserTemplate(path)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        return destinationURL
    }
}
