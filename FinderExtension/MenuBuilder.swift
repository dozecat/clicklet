import Cocoa
import FinderSync

enum MenuBuilder {
    static func makeMenu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "RightKit")

        switch menuKind {
        case .contextualMenuForItems:
            menu.addItem(withTitle: "Copy Path", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Compress", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Decompress", action: nil, keyEquivalent: "")
        case .contextualMenuForContainer, .contextualMenuForItemsInContainer, .toolbarItemMenu:
            menu.addItem(withTitle: "New File", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Copy Path", action: nil, keyEquivalent: "")
        @unknown default:
            break
        }

        return menu
    }
}
