import Foundation

/// Starter documents that RightKit always offers in the Finder "New File" menu.
///
/// This lives in `Shared/` on purpose: the Finder extension builds its menu from
/// the App Group snapshot, but it must still offer "New File" on a fresh install
/// before the main app has written that snapshot for the first time.
enum BuiltinTemplates {
    static let bundledDirectoryName = "BuiltinTemplates"

    /// Resource file names inside `Resources/BuiltinTemplates/`.
    // The three iWork templates have to be made by hand, in the apps themselves:
    // there is no way to synthesise a valid .pages/.numbers/.key from code, and a
    // zero-byte file with the right extension is not one — the app refuses it.
    // Drop the files in and the entries appear; without them they are hidden.
    static let pagesResourceName = "Empty.pages"
    static let numbersResourceName = "Empty.numbers"
    static let keynoteResourceName = "Empty.key"

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
        ),
        FileTemplate(
            id: "builtin.pages",
            name: "Pages",
            fileExtension: "pages",
            icon: "doc.richtext",
            contentSource: .bundledResource,
            contentPath: pagesResourceName,
            order: 60
        ),
        FileTemplate(
            id: "builtin.numbers",
            name: "Numbers",
            fileExtension: "numbers",
            icon: "tablecells",
            contentSource: .bundledResource,
            contentPath: numbersResourceName,
            order: 70
        ),
        FileTemplate(
            id: "builtin.key",
            name: "Keynote",
            fileExtension: "key",
            icon: "rectangle.on.rectangle",
            contentSource: .bundledResource,
            contentPath: keynoteResourceName,
            order: 80
        ),
        FileTemplate(
            id: "builtin.json",
            name: "JSON",
            fileExtension: "json",
            icon: "curlybraces",
            contentSource: .emptyText,
            contentPath: nil,
            order: 90
        ),
        FileTemplate(
            id: "builtin.html",
            name: "HTML",
            fileExtension: "html",
            icon: "chevron.left.forwardslash.chevron.right",
            contentSource: .emptyText,
            contentPath: nil,
            order: 100
        ),
        FileTemplate(
            id: "builtin.css",
            name: "CSS",
            fileExtension: "css",
            icon: "paintbrush",
            contentSource: .emptyText,
            contentPath: nil,
            order: 110,
            defaultEnabled: false
        ),
        FileTemplate(
            id: "builtin.js",
            name: "JavaScript",
            fileExtension: "js",
            icon: "curlybraces",
            contentSource: .emptyText,
            contentPath: nil,
            order: 120,
            defaultEnabled: false
        ),
        FileTemplate(
            id: "builtin.py",
            name: "Python",
            fileExtension: "py",
            icon: "chevron.left.forwardslash.chevron.right",
            iconResourcePath: "BuiltinScripts/Run Python/icon.png",
            contentSource: .emptyText,
            contentPath: nil,
            order: 130,
            defaultEnabled: false
        ),
        FileTemplate(
            id: "builtin.sh",
            name: "Shell",
            fileExtension: "sh",
            icon: "terminal",
            contentSource: .emptyText,
            contentPath: nil,
            order: 140,
            defaultEnabled: false
        ),
        FileTemplate(
            id: "builtin.yml",
            name: "YAML",
            fileExtension: "yml",
            icon: "list.bullet.rectangle",
            contentSource: .emptyText,
            contentPath: nil,
            order: 150,
            defaultEnabled: false
        ),
        FileTemplate(
            id: "builtin.csv",
            name: "CSV",
            fileExtension: "csv",
            icon: "tablecells",
            contentSource: .emptyText,
            contentPath: nil,
            order: 160,
            defaultEnabled: false
        ),
        FileTemplate(
            id: "builtin.rtf",
            name: "Rich Text",
            fileExtension: "rtf",
            icon: "doc.richtext",
            contentSource: .emptyText,
            contentPath: nil,
            order: 170,
            defaultEnabled: false
        )
    ]
}
