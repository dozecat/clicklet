import SwiftUI

@main
struct RightKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            GeneralView()
                .frame(width: 640, height: 420)
        }
    }
}
