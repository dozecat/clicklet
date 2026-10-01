import Foundation

/// Remembers which command each generated Finder menu item stands for.
///
/// Finder receives the menu built by the extension over XPC, and
/// `NSMenuItem.representedObject` does **not** survive that trip: it arrives as
/// `nil` whatever its type, verified by observation. What does survive is the
/// action selector, the target and the item's visible title (plus, apparently,
/// simple scalars such as `tag`). The command is therefore recovered from the
/// title, with the tag used first when it survived.
final class MenuCommandRegistry {
    private var templateIDsByTitle: [String: String] = [:]
    private var templateIDsByTag: [Int: String] = [:]
    private var scriptIDsByTitle: [String: String] = [:]
    private var scriptIDsByTag: [Int: String] = [:]
    private var nextTag = 1
    private let lock = NSLock()

    /// Called before building each menu: a stale entry would resolve a click to
    /// the wrong target.
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        templateIDsByTitle.removeAll()
        templateIDsByTag.removeAll()
        scriptIDsByTitle.removeAll()
        scriptIDsByTag.removeAll()
        nextTag = 1
    }

    @discardableResult
    func registerTemplate(title: String, id: String) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let tag = allocateTag()
        templateIDsByTag[tag] = id
        if templateIDsByTitle[title] == nil {
            templateIDsByTitle[title] = id
        }
        return tag
    }

    @discardableResult
    func registerScript(title: String, id: String) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let tag = allocateTag()
        scriptIDsByTag[tag] = id
        if scriptIDsByTitle[title] == nil {
            scriptIDsByTitle[title] = id
        }
        return tag
    }

    func templateID(title: String, tag: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if tag > 0, let id = templateIDsByTag[tag] {
            return id
        }
        return templateIDsByTitle[title]
    }

    func scriptID(title: String, tag: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if tag > 0, let id = scriptIDsByTag[tag] {
            return id
        }
        return scriptIDsByTitle[title]
    }

    private func allocateTag() -> Int {
        defer { nextTag += 1 }
        return nextTag
    }
}
