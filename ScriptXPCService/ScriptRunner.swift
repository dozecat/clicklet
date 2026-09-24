import Foundation

final class ScriptRunner: NSObject, ScriptXPCProtocol {
    func runScript(atPath path: String, arguments: [String], workingDirectory: String?, reply: @escaping (Int32) -> Void) {
        reply(0)
    }
}
