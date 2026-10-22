import AppKit
import WebKit
import WebAppWrapKit

/// A window holding any number of tabs. The title bar is hidden and replaced by a
/// TabStripView, with the traffic-light buttons moved down to sit inline with the tabs.
final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    static let stripHeight: CGFloat = 38
    private static let trafficLightX: CGFloat = 14
    private static let trafficLightSpacing: CGFloat = 20
    private static let stripInsetForTrafficLights: CGFloat = 82
    private static let stripInsetInFullScreen: CGFloat = 10

    private unowned let appDelegate: AppDelegate
    private let tabStrip = TabStripView()
    private let contentContainer = NSView()
    private(set) var tabs: [Tab] = []
    private(set) var selectedTab: Tab?
    /// The buttons at the right end of the tab strip: Extensions (shown once any are loaded)
    /// and More (the kebab menu).
    private let accessoryStack = NSStackView()
    private let extensionsButton = TitleBarButton(image: TitleBarButton.extensionsImage, label: "Extensions")
    private let moreButton = TitleBarButton(image: TitleBarButton.kebabImage, label: "More")
    /// How many recent pages the More menu's History submenu lists.
    private static let recentHistoryCount = 15

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // macOS otherwise treats the whole top of the window as a drag handle, which swallows
        // tab drags. TabStripView moves the window itself when its background is dragged.
        window.isMovable = false
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.minSize = NSSize(width: 480, height: 320)
        window.title = appDelegate.config.appName

        super.init(window: window)
        window.delegate = self

        let root = NSView()
        window.contentView = root
        for view in [tabStrip, contentContainer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            tabStrip.topAnchor.constraint(equalTo: root.topAnchor),
            tabStrip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabStrip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabStrip.heightAnchor.constraint(equalToConstant: Self.stripHeight),
            contentContainer.topAnchor.constraint(equalTo: tabStrip.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        tabStrip.leadingInset = Self.stripInsetForTrafficLights
        let palette = StripPalette(color: appDelegate.config.titleBarColor)
        tabStrip.palette = palette
        window.backgroundColor = palette.background
        tabStrip.onSelect = { [weak self] index in
            guard let self, self.tabs.indices.contains(index) else { return }
            self.select(self.tabs[index])
        }
        tabStrip.onClose = { [weak self] index in
            guard let self, self.tabs.indices.contains(index) else { return }
            self.closeTab(self.tabs[index])
        }
        tabStrip.onNewTab = { [weak self] in self?.newTab(nil) }
        tabStrip.onMove = { [weak self] from, to in self?.moveTab(from: from, to: to) }
        // AppKit re-lays out the title bar on resize, focus and appearance changes; put the buttons back each time.
        tabStrip.onLayout = { [weak self] in self?.layoutTrafficLights() }

        accessoryStack.orientation = .horizontal
        accessoryStack.spacing = 0
        for button in [extensionsButton, moreButton] {
            button.contentTintColor = palette.foreground.withAlphaComponent(0.7)
            button.hoverColor = palette.foreground
            accessoryStack.addArrangedSubview(button)
        }
        extensionsButton.isHidden = true
        extensionsButton.onPress = { [weak self] button in self?.showExtensionsMenu(from: button) }
        moreButton.onPress = { [weak self] button in self?.showMoreMenu(from: button) }
        tabStrip.trailingAccessory = accessoryStack
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Tabs

    /// Adds a tab. Link-opened tabs go right after their opener; others go at the end, or at
    /// `index` when an extension asks for a position.
    /// Pass `url: nil` with WebKit's `configuration` when WebKit itself will load the page.
    @discardableResult
    func openTab(
        url: URL?,
        configuration: WKWebViewConfiguration? = nil,
        after opener: Tab? = nil,
        at requestedIndex: Int? = nil,
        activate: Bool = true
    ) -> Tab {
        let tab = Tab(
            appDelegate: appDelegate,
            configuration: configuration ?? appDelegate.makeWebViewConfiguration()
        )
        tab.host = self
        // Lay the page out at the real size even while it loads in the background.
        tab.webView.frame = contentContainer.bounds
        tab.webView.autoresizingMask = [.width, .height]

        var index = opener.flatMap { tabs.firstIndex(of: $0) }.map { $0 + 1 } ?? tabs.count
        if let requestedIndex, (0...tabs.count).contains(requestedIndex) { index = requestedIndex }
        tabs.insert(tab, at: index)
        #if compiler(>=6.1)
        if #available(macOS 15.4, *) {
            extensionController?.didOpenTab(tab)
        }
        #endif

        if activate || selectedTab == nil {
            select(tab)
        } else {
            refreshStrip()
        }
        if let url { tab.load(url) }
        return tab
    }

    func select(_ tab: Tab) {
        guard tabs.contains(tab) else { return }
        if selectedTab !== tab {
            let previous = selectedTab
            selectedTab?.webView.removeFromSuperview()
            tab.webView.frame = contentContainer.bounds
            contentContainer.addSubview(tab.webView)
            selectedTab = tab
            #if compiler(>=6.1)
            if #available(macOS 15.4, *) {
                extensionController?.didActivateTab(tab, previousActiveTab: previous)
            }
            #endif
            refreshExtensionToolbar()
        }
        window?.makeFirstResponder(tab.webView)
        tabDidChange(tab)
    }

    /// Closing the last tab closes the window; closing the last window quits the app.
    func closeTab(_ tab: Tab) {
        guard let index = tabs.firstIndex(of: tab) else { return }
        guard tabs.count > 1 else {
            window?.close()
            return
        }
        tabs.remove(at: index)
        #if compiler(>=6.1)
        if #available(macOS 15.4, *) {
            extensionController?.didCloseTab(tab, windowIsClosing: false)
        }
        #endif
        tab.tearDown()
        if selectedTab === tab {
            selectedTab = nil
            select(tabs[min(index, tabs.count - 1)])
        } else {
            refreshStrip()
        }
    }

    /// Reorders after a tab is dragged in the strip.
    func moveTab(from source: Int, to destination: Int) {
        guard tabs.indices.contains(source), tabs.indices.contains(destination), source != destination else { return }
        let tab = tabs.remove(at: source)
        tabs.insert(tab, at: destination)
        #if compiler(>=6.1)
        if #available(macOS 15.4, *) {
            extensionController?.didMoveTab(tab, from: source, in: self)
        }
        #endif
        refreshStrip()
    }

    func tabDidChange(_ tab: Tab) {
        if tab === selectedTab {
            window?.title = tab.displayTitle
        }
        #if compiler(>=6.1)
        if #available(macOS 15.4, *), tabs.contains(tab) {
            extensionController?.didChangeTabProperties([.title, .loading, .URL], for: tab)
        }
        #endif
        refreshStrip()
    }

    // MARK: - Extensions

    #if compiler(>=6.1)
    @available(macOS 15.4, *)
    private var extensionController: WKWebExtensionController? {
        appDelegate.extensionHost?.controller
    }
    #endif

    /// The button an extension's popup is shown under: the Extensions button, since every
    /// extension's toolbar action lives in its menu.
    func toolbarButton(for extensionID: String) -> NSView? {
        extensionsButton.isHidden ? nil : extensionsButton
    }

    /// Shows the Extensions button once any extension is loaded. Called when extensions load
    /// or change, and on tab switches.
    func refreshExtensionToolbar() {
        #if compiler(>=6.1)
        guard #available(macOS 15.4, *), let host = appDelegate.extensionHost else { return }
        let isEmpty = host.loaded.isEmpty
        if extensionsButton.isHidden != isEmpty {
            extensionsButton.isHidden = isEmpty
            tabStrip.needsLayout = true
        }
        #endif
    }

    /// The Extensions menu under the button: each loaded extension, with its icon and badge for
    /// the selected tab. Choosing one clicks its toolbar button, and its popup opens under the
    /// Extensions button.
    private func showExtensionsMenu(from button: TitleBarButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        #if compiler(>=6.1)
        if #available(macOS 15.4, *), let host = appDelegate.extensionHost {
            let iconSize = CGSize(width: 16, height: 16)
            for item in host.loaded {
                let context = item.context
                let action = context.action(for: selectedTab)
                let entry = ClosureMenuItem(title: item.installed.name) { [weak self, weak host] in
                    guard let self, let host else { return }
                    host.performAction(context, for: self.selectedTab, anchor: self.extensionsButton)
                }
                let icon = action?.icon(for: iconSize) ?? context.webExtension.icon(for: iconSize)
                if let icon = icon?.copy() as? NSImage {
                    icon.size = iconSize
                    entry.image = icon
                }
                if let action {
                    entry.isEnabled = action.isEnabled
                    if !action.label.isEmpty, action.label != item.installed.name { entry.toolTip = action.label }
                    if !action.badgeText.isEmpty { entry.badge = NSMenuItemBadge(string: action.badgeText) }
                } else {
                    entry.isEnabled = false
                    entry.toolTip = "This extension has no toolbar button."
                }
                menu.addItem(entry)
            }
        }
        #endif
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ClosureMenuItem(title: "Manage Extensions in WebAppWrap…") {
            ExtensionsMenuController.openGenerator()
        })
        button.popUp(menu)
    }

    // MARK: - More menu, Open Link and History

    /// The kebab menu: open a link, recent history, and page commands.
    private func showMoreMenu(from button: TitleBarButton) {
        let menu = NSMenu()
        menu.addItem(menuItem("Open Link…", #selector(openLink(_:)), "l", [.command, .shift]))
        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        historyItem.submenu = makeHistoryMenu()
        menu.addItem(historyItem)
        let allowAll = menuItem("Allow All Sites", #selector(AppDelegate.toggleAllowAllSites(_:)), "")
        allowAll.state = appDelegate.allowedSites.allowsAll ? .on : .off
        allowAll.toolTip = "While on, every link opens in this app. Sites you visit are listed in Allowed Sites so you can save them."
        menu.addItem(allowAll)
        menu.addItem(menuItem("Allowed Sites…", #selector(AppDelegate.showAllowedSites(_:)), ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Copy Page Link", #selector(copyPageURL(_:)), "c", [.command, .shift]))
        menu.addItem(menuItem("Open Page in Browser", #selector(openPageInBrowser(_:)), "o", [.command, .shift]))
        button.popUp(menu)
    }

    /// Recently visited pages (choosing one opens it in this tab, or a new tab with ⌘),
    /// then Show All History.
    private func makeHistoryMenu() -> NSMenu {
        let menu = NSMenu()
        // Pages on sites no longer allowed are left out.
        let policy = appDelegate.linkPolicy
        let recent = appDelegate.history.history.recent(limit: Self.recentHistoryCount * 4)
            .filter { policy.isInternal($0.url) }
            .prefix(Self.recentHistoryCount)
        if recent.isEmpty {
            let empty = NSMenuItem(title: "No pages visited yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for entry in recent {
            let title = entry.displayTitle
            let url = entry.url
            let item = ClosureMenuItem(title: title.count > 60 ? String(title.prefix(59)) + "…" : title) { [weak self] in
                guard let self else { return }
                if NSApp.currentEvent?.modifierFlags.contains(.command) == true || self.selectedTab == nil {
                    self.openTab(url: url)
                } else {
                    self.selectedTab?.load(url)
                }
            }
            item.toolTip = url.absoluteString
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Show All History", #selector(AppDelegate.showHistory(_:)), "y"))
        return menu
    }

    private func menuItem(
        _ title: String,
        _ action: Selector,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        // Nil target: the responder chain finds this window (or the app delegate) and checks
        // validateMenuItem, as the menu bar does.
        return item
    }

    /// Asks for a link, for example one copied from another browser, and opens it here.
    /// The field starts with the clipboard's link, if it holds one.
    @objc func openLink(_ sender: Any?) {
        let clipboard = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestion = clipboard.flatMap { text in
            !text.contains(where: \.isNewline) && InputNormalizer.normalizeURL(text) != nil ? text : nil
        }
        presentOpenLink(text: suggestion ?? "", error: nil)
    }

    private func presentOpenLink(text: String, error: String?) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Open Link"
        alert.informativeText = error ?? "Paste or type a web address on \(appDelegate.ownSite) or one of the app’s allowed sites."
        if error != nil { alert.alertStyle = .warning }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = text
        field.placeholderString = "https://…"
        field.lineBreakMode = .byTruncatingMiddle
        field.cell?.usesSingleLineMode = true
        alert.accessoryView = field
        alert.addButton(withTitle: "Open in New Tab")
        alert.addButton(withTitle: "Open in This Tab")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response != .alertThirdButtonReturn else { return }
            let input = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = InputNormalizer.normalizeURL(input) else {
                if input.isEmpty { return }
                // Shown again after this sheet has finished closing.
                DispatchQueue.main.async {
                    self.presentOpenLink(text: input, error: "“\(input)” isn’t a web address. Enter one like example.com or https://example.com/page.")
                }
                return
            }
            let inNewTab = response != .alertSecondButtonReturn
            guard self.appDelegate.linkPolicy.isInternal(url) else {
                DispatchQueue.main.async { self.offerToAllow(url, typed: input, inNewTab: inNewTab) }
                return
            }
            self.open(url, inNewTab: inNewTab)
        }
    }

    private func open(_ url: URL, inNewTab: Bool) {
        if !inNewTab, let tab = selectedTab {
            tab.load(url)
        } else {
            openTab(url: url)
        }
    }

    /// Open Link was given a page outside the app's sites: it's not opened unless its site is
    /// added to Allowed Sites.
    private func offerToAllow(_ url: URL, typed: String, inNewTab: Bool) {
        guard let window, let domain = LinkPolicy.domain(of: url) else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(domain) isn’t allowed in \(appDelegate.config.appName)"
        alert.informativeText = """
        This app opens pages on \(appDelegate.ownSite) and its allowed sites only. \
        Add \(domain) to Allowed Sites to open this link here.
        """
        alert.addButton(withTitle: "Allow \(domain) and Open")
        alert.addButton(withTitle: "Edit Link")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.appDelegate.allowedSites.add(domain)
                self.open(url, inNewTab: inNewTab)
            case .alertSecondButtonReturn:
                DispatchQueue.main.async { self.presentOpenLink(text: typed, error: nil) }
            default:
                break
            }
        }
    }

    private func refreshStrip() {
        tabStrip.update(
            items: tabs.map { TabStripView.Item(title: $0.displayTitle, isLoading: $0.webView.isLoading) },
            selectedIndex: selectedTab.flatMap { tabs.firstIndex(of: $0) }
        )
    }

    private func selectTab(offset: Int) {
        guard let selectedTab, let index = tabs.firstIndex(of: selectedTab), tabs.count > 1 else { return }
        select(tabs[(index + offset + tabs.count) % tabs.count])
    }

    // MARK: - Traffic lights

    /// Moves the close/minimize/zoom buttons so they're vertically centered in the tab strip.
    /// The title bar container is shrunk to just the buttons' corner so the rest of the bar's
    /// clicks reach the tab strip.
    private func layoutTrafficLights() {
        guard let window, !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let minimize = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let titlebar = close.superview,
              let titlebarContainer = titlebar.superview
        else { return }

        let height = Self.stripHeight
        let containerFrame = NSRect(
            x: 0, y: window.frame.height - height,
            width: Self.stripInsetForTrafficLights, height: height
        )
        if titlebarContainer.frame != containerFrame {
            titlebarContainer.frame = containerFrame
            titlebar.frame = titlebarContainer.bounds
        }
        for (index, button) in [close, minimize, zoom].enumerated() {
            let origin = NSPoint(
                x: Self.trafficLightX + CGFloat(index) * Self.trafficLightSpacing,
                y: ((height - button.frame.height) / 2).rounded()
            )
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }

    func windowDidResize(_ notification: Notification) { layoutTrafficLights() }
    func windowDidBecomeKey(_ notification: Notification) {
        layoutTrafficLights()
        #if compiler(>=6.1)
        if #available(macOS 15.4, *) {
            extensionController?.didFocusWindow(self)
        }
        #endif
    }
    func windowDidResignKey(_ notification: Notification) { layoutTrafficLights() }

    func windowWillEnterFullScreen(_ notification: Notification) {
        // The traffic lights move into the hidden menu-bar overlay in full screen.
        tabStrip.leadingInset = Self.stripInsetInFullScreen
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        tabStrip.leadingInset = Self.stripInsetForTrafficLights
        layoutTrafficLights()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        layoutTrafficLights()
    }

    func windowWillClose(_ notification: Notification) {
        #if compiler(>=6.1)
        if #available(macOS 15.4, *), let extensionController {
            tabs.forEach { extensionController.didCloseTab($0, windowIsClosing: true) }
            extensionController.didCloseWindow(self)
        }
        #endif
        tabs.forEach { $0.tearDown() }
        tabs = []
        selectedTab = nil
        appDelegate.windowDidClose(self)
    }

    // MARK: - Menu actions

    @objc func newTab(_ sender: Any?) {
        openTab(url: appDelegate.config.baseURL)
    }

    @objc func closeCurrentTab(_ sender: Any?) {
        if let selectedTab { closeTab(selectedTab) } else { window?.close() }
    }

    @objc func closeWindow(_ sender: Any?) {
        window?.close()
    }

    @objc func showNextTab(_ sender: Any?) {
        selectTab(offset: 1)
    }

    @objc func showPreviousTab(_ sender: Any?) {
        selectTab(offset: -1)
    }

    /// cmd+1 ... cmd+8 select that tab, cmd+9 selects the last one.
    @objc func selectTabByNumber(_ sender: NSMenuItem) {
        let index = sender.tag == 9 ? tabs.count - 1 : sender.tag - 1
        guard tabs.indices.contains(index) else { return }
        select(tabs[index])
    }

    @objc func reloadPage(_ sender: Any?) {
        selectedTab?.reload()
    }

    @objc func navigateBack(_ sender: Any?) {
        selectedTab?.webView.goBack()
    }

    @objc func navigateForward(_ sender: Any?) {
        selectedTab?.webView.goForward()
    }

    @objc func goHome(_ sender: Any?) {
        selectedTab?.load(appDelegate.config.baseURL)
    }

    @objc func zoomInPage(_ sender: Any?) {
        selectedTab?.zoomIn()
    }

    @objc func zoomOutPage(_ sender: Any?) {
        selectedTab?.zoomOut()
    }

    @objc func resetPageZoom(_ sender: Any?) {
        selectedTab?.resetZoom()
    }

    @objc func copyPageURL(_ sender: Any?) {
        guard let url = selectedTab?.webView.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @objc func openPageInBrowser(_ sender: Any?) {
        guard let url = selectedTab?.webView.url, url.scheme?.hasPrefix("http") == true else { return }
        NSWorkspace.shared.open(url)
    }

    /// Opens Web Inspector for the current tab (also available via right-click > Inspect Element).
    @objc func showWebInspector(_ sender: Any?) {
        selectedTab?.showWebInspector()
    }

    @objc func reloadIgnoringCache(_ sender: Any?) {
        selectedTab?.webView.reloadFromOrigin()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let webView = selectedTab?.webView
        switch menuItem.action {
        case #selector(navigateBack(_:)): return webView?.canGoBack ?? false
        case #selector(navigateForward(_:)): return webView?.canGoForward ?? false
        case #selector(copyPageURL(_:)), #selector(openPageInBrowser(_:)): return webView?.url != nil
        case #selector(showNextTab(_:)), #selector(showPreviousTab(_:)): return tabs.count > 1
        default: return true
        }
    }
}
