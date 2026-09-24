import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override var toolbarItemName: String {
        "RightKit"
    }

    override var toolbarItemToolTip: String {
        "RightKit"
    }

    override var toolbarItemImage: NSImage {
        NSImage(named: NSImage.actionTemplateName) ?? NSImage()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        MenuBuilder.makeMenu(for: menuKind)
    }

    @IBAction func newFile(_ sender: AnyObject?) {
    }

    @IBAction func copyPath(_ sender: AnyObject?) {
    }

    @IBAction func compress(_ sender: AnyObject?) {
    }

    @IBAction func decompress(_ sender: AnyObject?) {
    }
}
