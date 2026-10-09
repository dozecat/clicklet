import Foundation

@objc public protocol ScriptXPCProtocol {
    func executeScript(_ requestData: Data, reply: @escaping (Data) -> Void)
}

enum XPCService {
    static let scriptServiceName = "com.dozecat.Clicklet.ScriptXPCService"
}
