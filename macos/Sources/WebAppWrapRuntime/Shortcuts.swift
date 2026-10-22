import AppKit

/// A key plus modifiers, as a menu item's key equivalent. Letters are stored lowercase, with
/// Shift in `modifiers` when it's held. Other keys are stored as the character they type (so
/// ⇧⌘] is "}" with ⌘), except Tab, which keeps Shift.
struct KeyShortcut: Codable, Hashable {
    var key: String
    var modifiers: UInt

    static let backTab = String(UnicodeScalar(UInt8(NSBackTabCharacter)))
    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(_ key: String, _ flags: NSEvent.ModifierFlags = .command) {
        self.key = key
        self.modifiers = flags.intersection(Self.relevantModifiers).rawValue
    }

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.relevantModifiers)
    }

    /// What the user pressed, or nil for keys that can't be a shortcut: plain typing keys
    /// (a shortcut needs ⌘, ⌃ or ⌥, except the F keys) and modifier keys on their own.
    init?(event: NSEvent) {
        var flags = event.modifierFlags.intersection(Self.relevantModifiers)
        guard let typed = event.charactersIgnoringModifiers, let scalar = typed.unicodeScalars.first else { return nil }
        let isFKey = (UInt32(NSF1FunctionKey)...UInt32(NSF35FunctionKey)).contains(scalar.value)
        let isFunctionKey = (0xF700...0xF8FF).contains(scalar.value)
        let key: String
        switch event.keyCode {
        case 48: // Tab
            key = flags.contains(.shift) ? Self.backTab : "\t"
        case 36, 76: // Return, Enter
            key = "\r"
        case 51: // Delete
            key = String(UnicodeScalar(UInt8(NSBackspaceCharacter)))
        default:
            if isFunctionKey {
                key = String(scalar)
            } else {
                let unshifted = event.characters(byApplyingModifiers: []) ?? typed
                if unshifted.count == 1, unshifted.first?.isLetter == true {
                    key = unshifted.lowercased()
                } else if flags.contains(.shift), typed != unshifted, !typed.isEmpty {
                    // ⇧⌘= is stored as ⌘+, which is how menus match it.
                    key = typed
                    flags.remove(.shift)
                } else {
                    key = unshifted.lowercased()
                }
            }
        }
        guard !key.isEmpty else { return nil }
        guard isFKey || !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        self.init(key, flags)
    }

    /// "⇧⌘L", "⌃⇥", "⌘+".
    var display: String {
        var text = ""
        let flags = self.flags
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + Self.keyName(key)
    }

    private static func keyName(_ key: String) -> String {
        guard let scalar = key.unicodeScalars.first else { return key }
        let value = Int(scalar.value)
        if (NSF1FunctionKey...NSF35FunctionKey).contains(value) {
            return "F\(value - NSF1FunctionKey + 1)"
        }
        switch value {
        case 0x09, NSBackTabCharacter: return "⇥"
        case 0x0D, 0x03: return "↩"
        case 0x20: return "Space"
        case 0x1B: return "⎋"
        case NSBackspaceCharacter, NSDeleteCharacter: return "⌫"
        case NSDeleteFunctionKey: return "⌦"
        case NSUpArrowFunctionKey: return "↑"
        case NSDownArrowFunctionKey: return "↓"
        case NSLeftArrowFunctionKey: return "←"
        case NSRightArrowFunctionKey: return "→"
        case NSHomeFunctionKey: return "↖"
        case NSEndFunctionKey: return "↘"
        case NSPageUpFunctionKey: return "⇞"
        case NSPageDownFunctionKey: return "⇟"
        default: return key.uppercased()
        }
    }
}

/// A menu command whose shortcuts can be changed in the Keyboard Shortcuts window.
/// The first shortcut is shown in the menu; the others work too, from hidden menu items.
struct ShortcutCommand {
    let id: String
    let title: String
    let section: String
    let action: Selector
    var tag: Int = 0
    /// False for commands that only exist as shortcuts (Select Tab 1 ... 9).
    var showsInMenu = true
    var defaults: [KeyShortcut] = []

    /// Every command, in menu order.
    static let all: [ShortcutCommand] = {
        var list: [ShortcutCommand] = [
            .init(id: "about", title: "About", section: "App", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .init(id: "keyboardShortcuts", title: "Keyboard Shortcuts…", section: "App", action: #selector(AppDelegate.showKeyboardShortcuts(_:))),
            // ⌘H is taken by Show Previous Tab, so Hide has no shortcut.
            .init(id: "hide", title: "Hide", section: "App", action: #selector(NSApplication.hide(_:))),
            .init(id: "hideOthers", title: "Hide Others", section: "App", action: #selector(NSApplication.hideOtherApplications(_:)), defaults: [.init("h", [.command, .option])]),
            .init(id: "showAll", title: "Show All", section: "App", action: #selector(NSApplication.unhideAllApplications(_:))),
            .init(id: "quit", title: "Quit", section: "App", action: #selector(NSApplication.terminate(_:)), defaults: [.init("q")]),

            .init(id: "newTab", title: "New Tab", section: "File", action: #selector(BrowserWindowController.newTab(_:)), defaults: [.init("t")]),
            .init(id: "newWindow", title: "New Window", section: "File", action: #selector(AppDelegate.newWindow(_:)), defaults: [.init("n")]),
            .init(id: "openLink", title: "Open Link…", section: "File", action: #selector(BrowserWindowController.openLink(_:)), defaults: [.init("l", [.command, .shift])]),
            .init(id: "closeTab", title: "Close Tab", section: "File", action: #selector(BrowserWindowController.closeCurrentTab(_:)), defaults: [.init("w")]),
            .init(id: "closeWindow", title: "Close Window", section: "File", action: #selector(BrowserWindowController.closeWindow(_:)), defaults: [.init("w", [.command, .shift])]),
            .init(id: "copyPageLink", title: "Copy Page Link", section: "File", action: #selector(BrowserWindowController.copyPageURL(_:)), defaults: [.init("c", [.command, .shift])]),
            .init(id: "openInBrowser", title: "Open Page in Browser", section: "File", action: #selector(BrowserWindowController.openPageInBrowser(_:)), defaults: [.init("o", [.command, .shift])]),

            .init(id: "reload", title: "Reload Page", section: "View", action: #selector(BrowserWindowController.reloadPage(_:)), defaults: [.init("r")]),
            .init(id: "actualSize", title: "Actual Size", section: "View", action: #selector(BrowserWindowController.resetPageZoom(_:)), defaults: [.init("0")]),
            .init(id: "zoomIn", title: "Zoom In", section: "View", action: #selector(BrowserWindowController.zoomInPage(_:)), defaults: [.init("=")]),
            .init(id: "zoomOut", title: "Zoom Out", section: "View", action: #selector(BrowserWindowController.zoomOutPage(_:)), defaults: [.init("-")]),
            .init(id: "fullScreen", title: "Enter Full Screen", section: "View", action: #selector(NSWindow.toggleFullScreen(_:)), defaults: [.init("f", [.command, .control])]),

            .init(id: "back", title: "Back", section: "History", action: #selector(BrowserWindowController.navigateBack(_:)), defaults: [.init("[")]),
            .init(id: "forward", title: "Forward", section: "History", action: #selector(BrowserWindowController.navigateForward(_:)), defaults: [.init("]")]),
            .init(id: "home", title: "Home", section: "History", action: #selector(BrowserWindowController.goHome(_:)), defaults: [.init("h", [.command, .shift])]),
            .init(id: "showHistory", title: "Show All History", section: "History", action: #selector(AppDelegate.showHistory(_:)), defaults: [.init("y")]),

            .init(id: "webInspector", title: "Show Web Inspector", section: "Developer", action: #selector(BrowserWindowController.showWebInspector(_:)), defaults: [.init("i", [.command, .option])]),
            .init(id: "reloadIgnoringCache", title: "Reload Ignoring Cache", section: "Developer", action: #selector(BrowserWindowController.reloadIgnoringCache(_:)), defaults: [.init("r", [.command, .option])]),

            .init(id: "minimize", title: "Minimize", section: "Window", action: #selector(NSWindow.performMiniaturize(_:)), defaults: [.init("m")]),
            .init(id: "zoom", title: "Zoom", section: "Window", action: #selector(NSWindow.performZoom(_:))),
            .init(id: "previousTab", title: "Show Previous Tab", section: "Window", action: #selector(BrowserWindowController.showPreviousTab(_:)),
                  defaults: [.init("h"), .init("{"), .init(KeyShortcut.backTab, [.control, .shift])]),
            .init(id: "nextTab", title: "Show Next Tab", section: "Window", action: #selector(BrowserWindowController.showNextTab(_:)),
                  defaults: [.init("l"), .init("}"), .init("\t", .control)]),
        ]
        for number in 1...9 {
            list.append(.init(
                id: number == 9 ? "selectLastTab" : "selectTab\(number)",
                title: number == 9 ? "Select Last Tab" : "Select Tab \(number)",
                section: "Window",
                action: #selector(BrowserWindowController.selectTabByNumber(_:)),
                tag: number,
                showsInMenu: false,
                defaults: [.init("\(number)")]
            ))
        }
        list.append(.init(id: "bringAllToFront", title: "Bring All to Front", section: "Window", action: #selector(NSApplication.arrangeInFront(_:))))
        return list
    }()

    static let sections = ["App", "File", "View", "History", "Developer", "Window"]

    static func named(_ id: String) -> ShortcutCommand? {
        all.first { $0.id == id }
    }
}

/// The shortcuts in use: each command's defaults, unless the user changed them. Changes are
/// kept in this app's defaults, so each wrapped app has its own.
final class ShortcutStore: ObservableObject {
    private static let defaultsKey = "KeyboardShortcuts"

    /// Edit menu shortcuts, which can't be reassigned: text fields and pages rely on them.
    static let reserved: [KeyShortcut: String] = [
        .init("z"): "Undo",
        .init("z", [.command, .shift]): "Redo",
        .init("x"): "Cut",
        .init("c"): "Copy",
        .init("v"): "Paste",
        .init("v", [.command, .option, .shift]): "Paste and Match Style",
        .init("a"): "Select All",
    ]

    /// Commands the user changed, by ID. An empty list means "no shortcut".
    @Published private(set) var overrides: [String: [KeyShortcut]]
    var onChange: (() -> Void)?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: [KeyShortcut]].self, from: data) {
            overrides = saved.filter { ShortcutCommand.named($0.key) != nil }
        } else {
            overrides = [:]
        }
    }

    func shortcuts(for command: ShortcutCommand) -> [KeyShortcut] {
        overrides[command.id] ?? command.defaults
    }

    func shortcuts(for id: String) -> [KeyShortcut] {
        guard let command = ShortcutCommand.named(id) else { return [] }
        return shortcuts(for: command)
    }

    func isCustomized(_ command: ShortcutCommand) -> Bool {
        overrides[command.id] != nil
    }

    /// The command already using `shortcut`, other than `except`.
    func command(using shortcut: KeyShortcut, except: ShortcutCommand? = nil) -> ShortcutCommand? {
        ShortcutCommand.all.first { $0.id != except?.id && shortcuts(for: $0).contains(shortcut) }
    }

    /// Gives `command` these shortcuts, taking them away from any other command using them.
    /// Returns the commands they were taken from.
    @discardableResult
    func set(_ shortcuts: [KeyShortcut], for command: ShortcutCommand) -> [ShortcutCommand] {
        var unique: [KeyShortcut] = []
        for shortcut in shortcuts where !unique.contains(shortcut) { unique.append(shortcut) }
        var changed = overrides
        var takenFrom: [ShortcutCommand] = []
        for other in ShortcutCommand.all where other.id != command.id {
            let current = changed[other.id] ?? other.defaults
            let kept = current.filter { !unique.contains($0) }
            if kept.count != current.count {
                changed[other.id] = kept
                takenFrom.append(other)
            }
        }
        changed[command.id] = unique
        apply(changed)
        return takenFrom
    }

    func reset(_ command: ShortcutCommand) {
        var changed = overrides
        changed.removeValue(forKey: command.id)
        apply(changed)
    }

    func resetAll() {
        apply([:])
    }

    /// Drops overrides that match the defaults, then saves.
    private func apply(_ changed: [String: [KeyShortcut]]) {
        overrides = changed.filter { id, shortcuts in ShortcutCommand.named(id)?.defaults != shortcuts }
        if overrides.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        } else if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        onChange?()
    }

    // MARK: - Menu items

    /// The command's menu items: one visible item with its first shortcut, and a hidden item for
    /// each other shortcut. Commands that don't show in menus get only hidden items.
    func menuItems(for id: String, title: String? = nil) -> [NSMenuItem] {
        guard let command = ShortcutCommand.named(id) else { return [] }
        let shortcuts = self.shortcuts(for: command)
        let title = title ?? command.title
        var items: [NSMenuItem] = []
        if command.showsInMenu {
            items.append(Self.item(command, title: title, shortcut: shortcuts.first))
        }
        for shortcut in shortcuts.dropFirst(command.showsInMenu ? 1 : 0) {
            let item = Self.item(command, title: title, shortcut: shortcut)
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
            items.append(item)
        }
        return items
    }

    /// One visible item for a command, for menus built on the fly such as the ⋮ menu.
    func menuItem(for id: String, title: String? = nil) -> NSMenuItem {
        guard let command = ShortcutCommand.named(id) else {
            return NSMenuItem(title: title ?? id, action: nil, keyEquivalent: "")
        }
        return Self.item(command, title: title ?? command.title, shortcut: shortcuts(for: command).first)
    }

    private static func item(_ command: ShortcutCommand, title: String, shortcut: KeyShortcut?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: command.action, keyEquivalent: shortcut?.key ?? "")
        item.keyEquivalentModifierMask = shortcut?.flags ?? []
        item.tag = command.tag
        return item
    }
}
