import Foundation

enum ScriptXPCClientError: LocalizedError {
    case invalidResponse
    case remoteFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The script service returned an invalid response."
        case let .remoteFailure(message):
            return message
        }
    }
}

final class ScriptXPCClient {
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func execute(_ request: ScriptJobRequest) async throws -> ScriptJobResult {
        let requestData = try encoder.encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate()
            let proxy = remoteProxy(errorHandler: { error in
                gate.resume {
                    continuation.resume(
                        throwing: ScriptXPCClientError.remoteFailure(error.localizedDescription)
                    )
                }
            })

            guard let scriptProxy = proxy as? ScriptXPCProtocol else {
                gate.resume {
                    continuation.resume(throwing: ScriptXPCClientError.invalidResponse)
                }
                return
            }

            scriptProxy.executeScript(requestData) { [decoder] responseData in
                gate.resume {
                    do {
                        continuation.resume(
                            returning: try decoder.decode(ScriptJobResult.self, from: responseData)
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    func invalidate() {
        lock.lock()
        let connection = self.connection
        self.connection = nil
        lock.unlock()
        connection?.invalidate()
    }

    private func remoteProxy(errorHandler: @escaping (Error) -> Void) -> Any {
        let connection = activeConnection()
        let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler)
        return proxy
    }

    private func activeConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }

        if let connection {
            return connection
        }

        let connection = NSXPCConnection(serviceName: XPCService.scriptServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: ScriptXPCProtocol.self)
        connection.interruptionHandler = { [weak self] in
            self?.invalidate()
        }
        connection.invalidationHandler = { [weak self] in
            self?.invalidate()
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}

private final class ContinuationGate {
    private let lock = NSLock()
    private var hasResumed = false

    func resume(_ action: () -> Void) {
        lock.lock()
        guard !hasResumed else {
            lock.unlock()
            return
        }
        hasResumed = true
        lock.unlock()
        action()
    }
}
