import Foundation

struct ScriptConfig: Codable {
    var name: String?
    var icon: String?
    var context: ScriptContext?
    var multiple: Bool?
    var extensions: [String]?
    var confirm: Bool?
    var order: Int?
}

enum ScriptContext: String, Codable {
    case selection
    case files
    case folders
    case background
    case all
}

struct FileTemplate: Codable, Identifiable {
    var id: String
    var name: String
    var fileExtension: String
    var icon: String?
}
