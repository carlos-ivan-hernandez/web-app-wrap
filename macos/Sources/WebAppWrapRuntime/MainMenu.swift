import AppKit

/// Builds the menu bar in code (there is no nib). Menu items with a nil target travel
/// the responder chain, so tab actions land on the key tab's BrowserWindowController.
@MainActor
enum MainMenu {
    /// Builds the menu bar. Called again whenever a keyboard shortcut changes.
    static func install(appName: String, extensionsMenuDelegate: NSMenuDelegate, shortcuts: ShortcutStore) {
        let menuBar = NSMenu()
        let windowMenu = makeWindowMenu(shortcuts)

        menuBar.addItem(submenu(appName, makeAppMenu(appName: appName, shortcuts)))
        menuBar.addItem(submenu("File", makeFileMenu(shortcuts)))
        menuBar.addItem(submenu("Edit", makeEditMenu()))
        menuBar.addItem(submenu("View", makeViewMenu(shortcuts)))
        menuBar.addItem(submenu("History", makeHistoryMenu(shortcuts)))
        let extensionsMenu = NSMenu()
        // Filled in each time it opens.
        extensionsMenu.delegate = extensionsMenuDelegate
        menuBar.addItem(submenu("Extensions", extensionsMenu))
        menuBar.addItem(submenu("Developer", makeDeveloperMenu(shortcuts)))
        menuBar.addItem(submenu("Window", windowMenu))

        NSApp.mainMenu = menuBar
        // AppKit appends the list of open windows to this menu.
        NSApp.windowsMenu = windowMenu
    }

    /// Adds a command's items (see ShortcutStore.menuItems).
    private static func add(_ id: String, to menu: NSMenu, _ shortcuts: ShortcutStore, title: String? = nil) {
        for item in shortcuts.menuItems(for: id, title: title) { menu.addItem(item) }
    }

    private static func makeAppMenu(appName: String, _ shortcuts: ShortcutStore) -> NSMenu {
        let menu = NSMenu()
        add("about", to: menu, shortcuts, title: "About \(appName)")
        menu.addItem(.separator())
        add("keyboardShortcuts", to: menu, shortcuts)
        menu.addItem(.separator())
        add("hide", to: menu, shortcuts, title: "Hide \(appName)")
        add("hideOthers", to: menu, shortcuts)
        add("showAll", to: menu, shortcuts)
        menu.addItem(.separator())
        add("quit", to: menu, shortcuts, title: "Quit \(appName)")
        return menu
    }

    private static func makeFileMenu(_ shortcuts: ShortcutStore) -> NSMenu {
        let menu = NSMenu()
        add("newTab", to: menu, shortcuts)
        add("newWindow", to: menu, shortcuts)
        add("openLink", to: menu, shortcuts)
        menu.addItem(.separator())
        add("closeTab", to: menu, shortcuts)
        add("closeWindow", to: menu, shortcuts)
        menu.addItem(.separator())
        add("copyPageLink", to: menu, shortcuts)
        add("openInBrowser", to: menu, shortcuts)
        return menu
    }

    /// Standard text editing; these shortcuts can't be changed.
    private static func makeEditMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]))
        menu.addItem(item("Delete", #selector(NSText.delete(_:)), ""))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        return menu
    }

    private static func makeViewMenu(_ shortcuts: ShortcutStore) -> NSMenu {
        let menu = NSMenu()
        add("reload", to: menu, shortcuts)
        menu.addItem(.separator())
        add("actualSize", to: menu, shortcuts)
        add("zoomIn", to: menu, shortcuts)
        add("zoomOut", to: menu, shortcuts)
        menu.addItem(.separator())
        add("fullScreen", to: menu, shortcuts)
        return menu
    }

    private static func makeHistoryMenu(_ shortcuts: ShortcutStore) -> NSMenu {
        let menu = NSMenu()
        add("back", to: menu, shortcuts)
        add("forward", to: menu, shortcuts)
        add("home", to: menu, shortcuts)
        menu.addItem(.separator())
        add("showHistory", to: menu, shortcuts)
        return menu
    }

    private static func makeDeveloperMenu(_ shortcuts: ShortcutStore) -> NSMenu {
        let menu = NSMenu()
        add("webInspector", to: menu, shortcuts)
        add("reloadIgnoringCache", to: menu, shortcuts)
        return menu
    }

    private static func makeWindowMenu(_ shortcuts: ShortcutStore) -> NSMenu {
        let menu = NSMenu(title: "Window")
        add("minimize", to: menu, shortcuts)
        add("zoom", to: menu, shortcuts)
        menu.addItem(.separator())
        add("previousTab", to: menu, shortcuts)
        add("nextTab", to: menu, shortcuts)
        // ⌘1 ... ⌘9, without cluttering the menu.
        for number in 1...8 { add("selectTab\(number)", to: menu, shortcuts) }
        add("selectLastTab", to: menu, shortcuts)
        menu.addItem(.separator())
        add("bringAllToFront", to: menu, shortcuts)
        return menu
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }

    private static func item(
        _ title: String,
        _ action: Selector?,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
