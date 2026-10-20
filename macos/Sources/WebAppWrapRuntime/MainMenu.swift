import AppKit

/// Builds the menu bar in code (there is no nib). Menu items with a nil target travel
/// the responder chain, so tab actions land on the key tab's BrowserWindowController.
@MainActor
enum MainMenu {
    static func install(appName: String, extensionsMenuDelegate: NSMenuDelegate) {
        let menuBar = NSMenu()
        let windowMenu = makeWindowMenu()

        menuBar.addItem(submenu(appName, makeAppMenu(appName: appName)))
        menuBar.addItem(submenu("File", makeFileMenu()))
        menuBar.addItem(submenu("Edit", makeEditMenu()))
        menuBar.addItem(submenu("View", makeViewMenu()))
        menuBar.addItem(submenu("History", makeHistoryMenu()))
        let extensionsMenu = NSMenu()
        // Filled in each time it opens.
        extensionsMenu.delegate = extensionsMenuDelegate
        menuBar.addItem(submenu("Extensions", extensionsMenu))
        menuBar.addItem(submenu("Developer", makeDeveloperMenu()))
        menuBar.addItem(submenu("Window", windowMenu))

        NSApp.mainMenu = menuBar
        // AppKit appends the list of open windows to this menu.
        NSApp.windowsMenu = windowMenu
    }

    private static func makeAppMenu(appName: String) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""))
        menu.addItem(.separator())
        // ⌘H is taken by Show Previous Tab, so Hide has no shortcut.
        menu.addItem(item("Hide \(appName)", #selector(NSApplication.hide(_:)), ""))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func makeFileMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("New Tab", #selector(BrowserWindowController.newTab(_:)), "t"))
        menu.addItem(item("New Window", #selector(AppDelegate.newWindow(_:)), "n"))
        menu.addItem(.separator())
        menu.addItem(item("Close Tab", #selector(BrowserWindowController.closeCurrentTab(_:)), "w"))
        menu.addItem(item("Close Window", #selector(BrowserWindowController.closeWindow(_:)), "w", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Copy Page Link", #selector(BrowserWindowController.copyPageURL(_:)), "c", [.command, .shift]))
        menu.addItem(item("Open Page in Browser", #selector(BrowserWindowController.openPageInBrowser(_:)), "o", [.command, .shift]))
        return menu
    }

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

    private static func makeViewMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Reload Page", #selector(BrowserWindowController.reloadPage(_:)), "r"))
        menu.addItem(.separator())
        menu.addItem(item("Actual Size", #selector(BrowserWindowController.resetPageZoom(_:)), "0"))
        menu.addItem(item("Zoom In", #selector(BrowserWindowController.zoomInPage(_:)), "="))
        menu.addItem(item("Zoom Out", #selector(BrowserWindowController.zoomOutPage(_:)), "-"))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func makeHistoryMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Back", #selector(BrowserWindowController.navigateBack(_:)), "["))
        menu.addItem(item("Forward", #selector(BrowserWindowController.navigateForward(_:)), "]"))
        menu.addItem(item("Home", #selector(BrowserWindowController.goHome(_:)), "h", [.command, .shift]))
        return menu
    }

    private static func makeDeveloperMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Show Web Inspector", #selector(BrowserWindowController.showWebInspector(_:)), "i", [.command, .option]))
        menu.addItem(item("Reload Ignoring Cache", #selector(BrowserWindowController.reloadIgnoringCache(_:)), "r", [.command, .option]))
        return menu
    }

    private static func makeWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:)), ""))
        menu.addItem(.separator())
        menu.addItem(item("Show Previous Tab", #selector(BrowserWindowController.showPreviousTab(_:)), "h"))
        menu.addItem(item("Show Next Tab", #selector(BrowserWindowController.showNextTab(_:)), "l"))
        menu.addItem(hidden(item("Previous Tab", #selector(BrowserWindowController.showPreviousTab(_:)), "{")))
        menu.addItem(hidden(item("Next Tab", #selector(BrowserWindowController.showNextTab(_:)), "}")))

        // Browser-style alternates (ctrl+tab, ctrl+shift+tab) and cmd+1 ... cmd+9, without cluttering the menu.
        let backTab = String(UnicodeScalar(UInt8(NSBackTabCharacter)))
        menu.addItem(hidden(item("Next Tab", #selector(BrowserWindowController.showNextTab(_:)), "\t", .control)))
        menu.addItem(hidden(item("Previous Tab", #selector(BrowserWindowController.showPreviousTab(_:)), backTab, [.control, .shift])))
        for number in 1...9 {
            let title = number == 9 ? "Select Last Tab" : "Select Tab \(number)"
            let tabItem = item(title, #selector(BrowserWindowController.selectTabByNumber(_:)), "\(number)")
            tabItem.tag = number
            menu.addItem(hidden(tabItem))
        }

        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), ""))
        return menu
    }

    private static func hidden(_ item: NSMenuItem) -> NSMenuItem {
        item.isHidden = true
        item.allowsKeyEquivalentWhenHidden = true
        return item
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
