import Foundation
import ServiceManagement

/// Registers the app as a login item.
///
/// Uses `SMAppService`, the supported API since macOS 13; the older
/// `LSSharedFileList` approach is deprecated and does not work for sandboxed or
/// notarised apps.
enum LaunchAtLoginService {
    enum State: Equatable {
        case enabled
        case disabled
        case unavailable
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered, .notFound:
            return .disabled
        default:
            return .unavailable
        }
    }

    static func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
