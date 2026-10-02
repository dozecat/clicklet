import Cocoa
import FinderSync

enum MenuBuilder {
    /// `registry` records what each generated template/script item means. That
    /// mapping cannot travel with the menu itself, so it is kept in the extension
    /// process and resolved when the item is clicked (see `MenuCommandRegistry`).
    ///
    /// Toolbox items need no registry: each one has its own action selector.
    static func makeMenu(
        for menuKind: FIMenuKind,
        snapshot: MenuSnapshot?,
        selectedURLs: [URL],
        target: FinderSync,
        registry: MenuCommandRegistry
    ) -> NSMenu? {
        registry.reset()

        let menu = NSMenu(title: "RightKit")
        let scripts = snapshot?.scripts.filter {
            $0.isEnabled && matches($0, selectedURLs: selectedURLs)
        } ?? []
        // Falling back to the bundled catalog keeps the menu usable on a fresh
        // install, before the main app has written its first snapshot.
        let templates = snapshot?.templates ?? BuiltinTemplates.all
        let toolbox = (snapshot?.toolbox ?? ToolboxCatalog.defaultItems).filter(\.isEnabled)
        let icons = snapshot?.icons ?? [:]

        // Everything is driven by the toolbox list and its order; 新建文件 and
        // 脚本 render as submenus at their position in that list.
        switch menuKind {
        case .contextualMenuForItems:
            for item in toolbox where item.appliesToSelection {
                addToolboxEntry(
                    item,
                    background: false,
                    templates: templates,
                    scripts: scripts,
                    icons: icons,
                    registry: registry,
                    target: target,
                    to: menu
                )
            }
        case .contextualMenuForContainer:
            for item in toolbox where item.appliesToBackground {
                addToolboxEntry(
                    item,
                    background: true,
                    templates: templates,
                    scripts: scripts,
                    icons: icons,
                    registry: registry,
                    target: target,
                    to: menu
                )
            }
        case .contextualMenuForSidebar, .toolbarItemMenu:
            if let copyPath = toolbox.first(where: { $0.id == .copyPath && $0.appliesToBackground }) {
                addItem(
                    title: copyPath.title(forBackground: true),
                    action: #selector(FinderSync.copyPath(_:)),
                    icon: icons[MenuIconKey.toolbox(.copyPath)],
                    target: target,
                    to: menu
                )
            }
        @unknown default:
            return nil
        }

        return menu.items.isEmpty ? nil : menu
    }

    static func matches(_ script: ScriptPackage, selectedURLs: [URL]) -> Bool {
        if !script.allowsMultipleSelection, selectedURLs.count > 1 {
            return false
        }

        let directories = selectedURLs.map {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        let hasSelection = !selectedURLs.isEmpty
        let allFiles = hasSelection && directories.allSatisfy { !$0 }
        let allFolders = hasSelection && directories.allSatisfy(\.self)

        let contextMatches: Bool
        switch script.context {
        case .selection:
            contextMatches = hasSelection
        case .files:
            contextMatches = allFiles
        case .folders:
            contextMatches = allFolders
        case .background:
            contextMatches = !hasSelection
        case .all:
            contextMatches = true
        }
        guard contextMatches else {
            return false
        }

        guard !script.extensions.isEmpty else {
            return true
        }
        return allFiles && selectedURLs.allSatisfy {
            script.extensions.contains($0.pathExtension.lowercased())
        }
    }

    private static func addToolboxEntry(
        _ item: ToolboxItem,
        background: Bool,
        templates: [FileTemplate],
        scripts: [ScriptPackage],
        icons: [String: Data],
        registry: MenuCommandRegistry,
        target: FinderSync,
        to menu: NSMenu
    ) {
        switch item.id {
        case .newFile:
            addNewFileSubmenu(
                templates,
                icons: icons,
                registry: registry,
                target: target,
                to: menu
            )
        case .scripts:
            addScriptsSubmenu(
                scripts,
                icons: icons,
                registry: registry,
                target: target,
                to: menu
            )
        default:
            addItem(
                title: item.title(forBackground: background),
                action: selector(for: item.id),
                icon: icons[MenuIconKey.toolbox(item.id)],
                target: target,
                to: menu
            )
        }
    }

    /// The enabled scripts that match the current selection context, gathered
    /// under one 脚本 submenu instead of filling the top level.
    private static func addScriptsSubmenu(
        _ scripts: [ScriptPackage],
        icons: [String: Data],
        registry: MenuCommandRegistry,
        target: FinderSync,
        to menu: NSMenu
    ) {
        guard !scripts.isEmpty else {
            return
        }

        let item = NSMenuItem(title: "脚本", action: nil, keyEquivalent: "")
        item.image = image(MenuIconKey.toolbox(.scripts), in: icons)
        let submenu = NSMenu(title: "脚本")
        for script in scripts {
            let tag = registry.registerScript(title: script.name, id: script.id)
            addItem(
                title: script.name,
                action: #selector(FinderSync.runScript(_:)),
                tag: tag,
                icon: icons[MenuIconKey.script(script.id)],
                target: target,
                to: submenu
            )
        }
        item.submenu = submenu
        menu.addItem(item)
    }

    private static func addNewFileSubmenu(
        _ templates: [FileTemplate],
        icons: [String: Data],
        registry: MenuCommandRegistry,
        target: FinderSync,
        to menu: NSMenu
    ) {
        guard !templates.isEmpty else {
            return
        }

        let item = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        item.image = image(MenuIconKey.toolbox(.newFile), in: icons)
        let submenu = NSMenu(title: "新建文件")
        for template in templates {
            let tag = registry.registerTemplate(title: template.name, id: template.id)
            addItem(
                title: template.name,
                action: #selector(FinderSync.newFile(_:)),
                tag: tag,
                icon: icons[MenuIconKey.template(template.id)],
                target: target,
                to: submenu
            )
        }
        item.submenu = submenu
        menu.addItem(item)
    }

    private static func selector(for id: ToolboxItemID) -> Selector {
        switch id {
        case .newFile:
            // Rendered as a submenu; this is only a fallback.
            return #selector(FinderSync.newFile(_:))
        case .scripts:
            return #selector(FinderSync.runScript(_:))
        case .copyPath:
            return #selector(FinderSync.copyPath(_:))
        case .copyFileName:
            return #selector(FinderSync.copyFileName(_:))
        case .openInTerminal:
            return #selector(FinderSync.openInTerminal(_:))
        case .compressZip:
            return #selector(FinderSync.compressZip(_:))
        case .compressSevenZip:
            return #selector(FinderSync.compressSevenZip(_:))
        case .decompressHere:
            return #selector(FinderSync.decompressHere(_:))
        case .decompressIntoFolder:
            return #selector(FinderSync.decompressIntoFolder(_:))
        }
    }

    private static func addSeparator(to menu: NSMenu) {
        guard !menu.items.isEmpty, menu.items.last?.isSeparatorItem == false else {
            return
        }
        menu.addItem(.separator())
    }

    private static func addItem(
        title: String,
        action: Selector,
        tag: Int = 0,
        icon: Data? = nil,
        target: FinderSync,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.tag = tag
        if let icon, let image = NSImage(data: icon) {
            item.image = image
        }
        menu.addItem(item)
    }

    /// Builds the menu image for a key, or nil when the snapshot has none.
    private static func image(_ key: String, in icons: [String: Data]) -> NSImage? {
        guard let data = icons[key] else {
            return nil
        }
        return NSImage(data: data)
    }
}
