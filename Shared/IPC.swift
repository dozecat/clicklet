import Foundation

@objc public protocol ScriptXPCProtocol {
    func runScript(atPath path: String, arguments: [String], workingDirectory: String?, reply: @escaping (Int32) -> Void)
}

enum XPCService {
    static let scriptServiceName = "com.dozecat.RightKit.ScriptXPCService"
}
