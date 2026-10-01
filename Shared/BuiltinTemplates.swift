import Foundation

/// Starter documents that RightKit always offers in the Finder "New File" menu.
///
/// This lives in `Shared/` on purpose: the Finder extension builds its menu from
/// the App Group snapshot, but it must still offer "New File" on a fresh install
/// before the main app has written that snapshot for the first time.
enum BuiltinTemplates {
    static let bundledDirectoryName = "BuiltinTemplates"

    /// Resource file names inside `Resources/BuiltinTemplates/`.
    static let wordResourceName = "Empty.docx"
    static let excelResourceName = "Empty.xlsx"
    static let powerpointResourceName = "Empty.pptx"

    static let all: [FileTemplate] = [
        FileTemplate(
            id: "builtin.txt",
            name: "Text",
            fileExtension: "txt",
            icon: "doc.text",
            contentSource: .emptyText,
            contentPath: nil,
            order: 10
        ),
        FileTemplate(
            id: "builtin.md",
            name: "Markdown",
            fileExtension: "md",
            icon: "doc.richtext",
            contentSource: .emptyText,
            contentPath: nil,
            order: 20
        ),
        FileTemplate(
            id: "builtin.docx",
            name: "Word",
            fileExtension: "docx",
            icon: "doc.text",
            contentSource: .bundledResource,
            contentPath: wordResourceName,
            order: 30
        ),
        FileTemplate(
            id: "builtin.xlsx",
            name: "Excel",
            fileExtension: "xlsx",
            icon: "tablecells",
            contentSource: .bundledResource,
            contentPath: excelResourceName,
            order: 40
        ),
        FileTemplate(
            id: "builtin.pptx",
            name: "PowerPoint",
            fileExtension: "pptx",
            icon: "rectangle.on.rectangle",
            contentSource: .bundledResource,
            contentPath: powerpointResourceName,
            order: 50
        )
    ]
}
