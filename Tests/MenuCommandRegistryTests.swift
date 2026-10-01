import AppKit
import XCTest

/// The command behind a menu item cannot travel with the item: Finder receives
/// the menu over XPC and `NSMenuItem.representedObject` always arrives `nil`.
/// These tests pin the in-process lookup that replaced it.
final class MenuCommandRegistryTests: XCTestCase {
    func testResolvesTemplateByTitle() {
        let registry = MenuCommandRegistry()
        registry.registerTemplate(title: "Text", id: "builtin.txt")

        XCTAssertEqual(registry.templateID(title: "Text", tag: 0), "builtin.txt")
    }

    func testResolvesTemplateByTag() {
        let registry = MenuCommandRegistry()
        let tag = registry.registerTemplate(title: "Text", id: "builtin.txt")

        XCTAssertGreaterThan(tag, 0)
        XCTAssertEqual(registry.templateID(title: "renamed by Finder", tag: tag), "builtin.txt")
    }

    func testTagWinsOverTitleSoDuplicateTitlesStayCorrect() {
        let registry = MenuCommandRegistry()
        registry.registerTemplate(title: "Untitled", id: "user.a.txt")
        let secondTag = registry.registerTemplate(title: "Untitled", id: "user.b.txt")

        XCTAssertEqual(registry.templateID(title: "Untitled", tag: 0), "user.a.txt")
        XCTAssertEqual(registry.templateID(title: "Untitled", tag: secondTag), "user.b.txt")
    }

    func testTemplatesAndScriptsDoNotCollide() {
        let registry = MenuCommandRegistry()
        registry.registerTemplate(title: "Shared name", id: "builtin.txt")
        registry.registerScript(title: "Shared name", id: "Convert WebP")

        XCTAssertEqual(registry.templateID(title: "Shared name", tag: 0), "builtin.txt")
        XCTAssertEqual(registry.scriptID(title: "Shared name", tag: 0), "Convert WebP")
    }

    func testResetDropsStaleEntries() {
        let registry = MenuCommandRegistry()
        let tag = registry.registerTemplate(title: "Text", id: "builtin.txt")
        registry.reset()

        XCTAssertNil(registry.templateID(title: "Text", tag: 0))
        XCTAssertNil(registry.templateID(title: "Text", tag: tag))
    }

    func testUnknownTitleAndTagResolveToNil() {
        let registry = MenuCommandRegistry()
        registry.registerTemplate(title: "Text", id: "builtin.txt")

        XCTAssertNil(registry.templateID(title: "Markdown", tag: 0))
        XCTAssertNil(registry.templateID(title: "Markdown", tag: 99))
        XCTAssertNil(registry.scriptID(title: "Text", tag: 1))
    }

    /// The only values that provably reach Finder are the selector, the target
    /// and the title; `representedObject` is dropped. Guard the assumption that
    /// the title is what the run loop hands back.
    func testMenuItemKeepsTitleAndTag() {
        let item = NSMenuItem(title: "Text", action: nil, keyEquivalent: "")
        item.tag = 7

        XCTAssertEqual(item.title, "Text")
        XCTAssertEqual(item.tag, 7)
        XCTAssertNil(item.representedObject)
    }
}
