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
    /// Top edge of the window (from the top) that reveals the tab strip in full screen.
    private static let fullScreenRevealHeight: CGFloat = 6
    private static let stripHideDelay: TimeInterval = 0.4

    private unowned let appDelegate: AppDelegate
    private let tabStrip = TabStripView()
    private let contentContainer = NSView()
    private var stripHeightConstraint: NSLayoutConstraint!
    private var isFullScreen = false
    private var isStripRevealed = true
    private var fullScreenMouseMonitor: Any?
    private var hideStripWorkItem: DispatchWorkItem?
    /// The frame the user last gave the window on each arrangement of screens (see
    /// `screenLayout`). While the display sleeps, during the short display-off wakes a sleeping
    /// Mac makes, or while a monitor reconnects, macOS can report a smaller screen and shrink
    /// the window to fit. When the screens are back as they were, so is the window.
    private var framesByScreenLayout: [String: NSRect] = [:]
    private var lastScreenChange = Date.distantPast
    private var screensAreAsleep = false
    private var systemIsAsleep = false
    /// Frame changes this soon after a screen change are macOS fitting the window to the
    /// screens, not the user.
    private static let screenSettleTime: TimeInterval = 2
    private var sleepObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private(set) var tabs: [Tab] = []
    private(set) var selectedTab: Tab?
    /// The buttons at the right end of the tab strip: Extensions (shown once any are loaded)
    /// and More (the kebab menu).
    private let accessoryStack = NSStackView()
    private let extensionsButton = TitleBarButton(image: TitleBarButton.extensionsImage, label: "Extensions")
    private let moreButton = TitleBarButton(image: TitleBarButton.kebabImage, label: "More")
    /// Names this window's profile; shown once the app has more than one.
    private let profileButton = TitleBarButton(image: TitleBarButton.profileImage, label: "Profile")
    private var palette: StripPalette
    /// The Find box (⌘F), floating at the top right of the page.
    private let findBar = FindBar()
    /// The profile whose logins and site data this window's tabs use.
    let profileID: UUID
    /// How many recent pages the More menu's History submenu lists.
    private static let recentHistoryCount = 15

    init(appDelegate: AppDelegate, profileID: UUID) {
        self.appDelegate = appDelegate
        self.profileID = profileID
        self.palette = StripPalette(color: appDelegate.config.titleBarColor)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // macOS otherwise treats the whole top of the window as a drag handle, which swallows
        // tab drags. TabStripView starts a native window drag (with tiling) from its background.
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
        stripHeightConstraint = tabStrip.heightAnchor.constraint(equalToConstant: Self.stripHeight)
        NSLayoutConstraint.activate([
            tabStrip.topAnchor.constraint(equalTo: root.topAnchor),
            tabStrip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabStrip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stripHeightConstraint,
            contentContainer.topAnchor.constraint(equalTo: tabStrip.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        tabStrip.leadingInset = Self.stripInsetForTrafficLights

        findBar.translatesAutoresizingMaskIntoConstraints = false
        findBar.isHidden = true
        root.addSubview(findBar)
        NSLayoutConstraint.activate([
            findBar.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 8),
            findBar.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -16),
        ])
        findBar.onChange = { [weak self] _ in self?.runFind(backwards: false, fromStart: true) }
        findBar.onNext = { [weak self] in self?.runFind(backwards: false, fromStart: false) }
        findBar.onPrevious = { [weak self] in self?.runFind(backwards: true, fromStart: false) }
        findBar.onClose = { [weak self] in self?.closeFind() }

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
        for button in [profileButton, extensionsButton, moreButton] {
            accessoryStack.addArrangedSubview(button)
        }
        applyPalette()
        extensionsButton.isHidden = true
        extensionsButton.onPress = { [weak self] button in self?.showExtensionsMenu(from: button) }
        moreButton.onPress = { [weak self] button in self?.showMoreMenu(from: button) }
        profileButton.onPress = { [weak self] button in
            guard let self else { return }
            button.popUp(self.makeProfileMenu())
        }
        tabStrip.trailingAccessory = accessoryStack
        refreshProfile()
        observeSleepAndWake()
    }

    // MARK: - Title bar color

    /// Recolors the tab strip and its buttons, e.g. while a color is picked from the ⋮ menu.
    func setTitleBarColor(_ color: HexColor) {
        palette = StripPalette(color: color)
        applyPalette()
    }

    private func applyPalette() {
        tabStrip.palette = palette
        window?.backgroundColor = palette.background
        // Shows behind a tab's page until it first paints (see Tab).
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = palette.background.cgColor
        for button in [profileButton, extensionsButton, moreButton] {
            button.contentTintColor = palette.foreground.withAlphaComponent(0.7)
            button.hoverColor = palette.foreground
        }
        refreshProfile()
        tabStrip.needsDisplay = true
    }

    // MARK: - Sleep, wake and screen changes

    private func observeSleepAndWake() {
        let workspace = NSWorkspace.shared.notificationCenter
        let observe = { [weak self] (center: NotificationCenter, name: Notification.Name, action: @escaping (BrowserWindowController) -> Void) in
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let self { action(self) }
                }
            }
            self?.sleepObservers.append((center, token))
        }
        observe(workspace, NSWorkspace.willSleepNotification) {
            $0.rememberFrame()
            $0.systemIsAsleep = true
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) {
            $0.rememberFrame()
            $0.screensAreAsleep = true
        }
        observe(workspace, NSWorkspace.didWakeNotification) {
            $0.systemIsAsleep = false
            $0.screensDidChange()
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) {
            $0.screensAreAsleep = false
            $0.screensDidChange()
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.screensDidChange() }
    }

    private func stopObservingSleepAndWake() {
        for (center, token) in sleepObservers { center.removeObserver(token) }
        sleepObservers = []
    }

    /// The screens' sizes and positions, e.g. "{{0, 0}, {2560, 1440}}".
    private static var screenLayout: String {
        NSScreen.screens.map { NSStringFromRect($0.frame) }.sorted().joined(separator: " ")
    }

    /// True while macOS may be resizing the window to fit the screens rather than the user.
    private var screensAreSettling: Bool {
        screensAreAsleep || systemIsAsleep || Date().timeIntervalSince(lastScreenChange) < Self.screenSettleTime
    }

    /// Saves the window's frame for the current screens.
    private func rememberFrame() {
        guard !screensAreSettling, let window, window.isVisible, !window.isMiniaturized,
              !isFullScreen, !window.styleMask.contains(.fullScreen)
        else { return }
        framesByScreenLayout[Self.screenLayout] = window.frame
    }

    /// The window moved or resized. If the screens stay put, that's the user's choice.
    private func windowFrameDidChange() {
        guard !screensAreSettling else { return }
        appDelegate.tabsDidChange()
        // Checked again a moment later, since a resize caused by the screens can arrive just
        // before the notice that they changed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.rememberFrame()
        }
    }

    private func screensDidChange() {
        lastScreenChange = Date()
        relayoutContent()
        // Displays often come back a moment after the wake notice, one at a time, and macOS
        // can fit the window to them again shortly after.
        for delay in [0.0, 0.5, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.restoreFrameForScreens()
            }
        }
    }

    /// Puts back the frame the window had the last time the screens were arranged like this.
    private func restoreFrameForScreens() {
        guard !screensAreAsleep, !systemIsAsleep, let window, !window.isMiniaturized,
              !isFullScreen, !window.styleMask.contains(.fullScreen),
              let saved = framesByScreenLayout[Self.screenLayout], window.frame != saved,
              NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -1, dy: -1).intersects(saved) })
        else { return }
        window.setFrame(saved, display: true)
        relayoutContent()
    }

    /// Makes the tab strip, page and traffic lights match the window's current size.
    private func relayoutContent() {
        guard let window else { return }
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
        selectedTab?.webView.frame = contentContainer.bounds
        layoutTrafficLights()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        // Dragged by the user, so it counts even right after a screen change.
        guard let window, !isFullScreen else { return }
        framesByScreenLayout[Self.screenLayout] = window.frame
    }

    // MARK: - Profile

    /// Shows the profile's name in the title bar while the app has more than one profile.
    func refreshProfile() {
        let profiles = appDelegate.profiles
        let shows = profiles.hasSeveral
        let name = profiles.name(of: profileID)
        profileButton.setText(shows ? (name.count > 24 ? String(name.prefix(23)) + "…" : name) : nil,
                              color: palette.foreground.withAlphaComponent(0.85))
        profileButton.toolTip = "Profile: \(name)"
        if profileButton.isHidden == shows {
            profileButton.isHidden = !shows
        }
        tabStrip.needsLayout = true
    }

    /// Each profile (choosing one shows its window, or opens one), then New Profile and Manage Profiles.
    private func makeProfileMenu() -> NSMenu {
        let menu = NSMenu()
        let profiles = appDelegate.profiles
        for profile in profiles.list {
            let id = profile.id
            let item = ClosureMenuItem(title: profile.name) { [weak self] in
                self?.appDelegate.showProfile(id)
            }
            item.state = id == profileID ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        if Profiles.isSupported {
            menu.addItem(menuItem("New Profile…", #selector(AppDelegate.newProfile(_:)), ""))
        } else {
            let unsupported = NSMenuItem(title: "More profiles need macOS 14 or later", action: nil, keyEquivalent: "")
            unsupported.isEnabled = false
            menu.addItem(unsupported)
        }
        menu.addItem(menuItem("Manage Profiles…", #selector(AppDelegate.showProfiles(_:)), ""))
        return menu
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
            configuration: configuration ?? appDelegate.makeWebViewConfiguration(profile: profileID, for: url)
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
            if !findBar.isHidden {
                previous?.endFind()
                runFind(backwards: false, fromStart: true)
            }
        }
        if findBar.isHidden { window?.makeFirstResponder(tab.webView) }
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
                if let action, item.hasToolbarButton {
                    entry.isEnabled = action.isEnabled
                    if !action.label.isEmpty, action.label != item.installed.name { entry.toolTip = action.label }
                    if !action.badgeText.isEmpty { entry.badge = NSMenuItemBadge(string: action.badgeText) }
                } else {
                    // Nothing to click, but it's on: shown at full strength, without the hover
                    // highlight. A disabled item would look off.
                    entry.view = Self.unclickableMenuRow(
                        title: item.installed.name,
                        toolTip: "\(item.installed.name) has no toolbar button. It works on its own in pages."
                    )
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

    /// A menu row that looks like an enabled item but doesn't highlight or respond to clicks.
    /// Menu items with their own view don't highlight, so this draws the title itself, lined
    /// up with the titles of the other items.
    private static func unclickableMenuRow(title: String, toolTip: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        label.sizeToFit()
        // A label draws its text 2 points in, so 14 lines it up with items' 16.
        let leading: CGFloat = 14, height: CGFloat = 24
        let row = NSView(frame: NSRect(x: 0, y: 0, width: leading + label.frame.width + 20, height: height))
        label.frame.origin = NSPoint(x: leading, y: ((height - label.frame.height) / 2).rounded())
        row.addSubview(label)
        row.toolTip = toolTip
        return row
    }

    // MARK: - More menu, Open Link and History

    /// The kebab menu: open a link, recent history, sites, notifications, profiles, shortcuts
    /// and page commands.
    private func showMoreMenu(from button: TitleBarButton) {
        let menu = NSMenu()
        let shortcuts = appDelegate.shortcuts
        menu.addItem(shortcuts.menuItem(for: "openLink"))
        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        historyItem.submenu = makeHistoryMenu()
        menu.addItem(historyItem)
        let allowAll = menuItem("Allow All Sites", #selector(AppDelegate.toggleAllowAllSites(_:)), "")
        allowAll.state = appDelegate.allowedSites.allowsAll ? .on : .off
        allowAll.toolTip = "While on, every link opens in this app. Sites you visit are listed in Allowed Sites so you can save them."
        menu.addItem(allowAll)
        menu.addItem(menuItem("Allowed Sites…", #selector(AppDelegate.showAllowedSites(_:)), ""))
        menu.addItem(.separator())
        let notifications = appDelegate.notifications!
        let notify = menuItem("Notifications", #selector(AppDelegate.toggleNotifications(_:)), "")
        notify.state = notifications.isEnabled && notifications.isAllowedBySystem ? .on : .off
        notify.toolTip = "Shows the site’s notifications in macOS Notification Center."
        menu.addItem(notify)
        let reopen = menuItem("Reopen Tabs at Launch", #selector(AppDelegate.toggleReopenTabs(_:)), "")
        reopen.state = appDelegate.reopensTabs ? .on : .off
        reopen.toolTip = "Opens the windows and tabs that were open when \(appDelegate.config.appName) last quit."
        menu.addItem(reopen)
        let profileItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        profileItem.submenu = makeProfileMenu()
        menu.addItem(profileItem)
        let color = menuItem("Title Bar Color…", #selector(AppDelegate.showTitleBarColor(_:)), "")
        color.toolTip = appDelegate.config.appID == nil
            ? "This app wasn’t made from WebAppWrap’s list, so a color picked here lasts until it quits."
            : "Changes this bar’s color and saves it in WebAppWrap for this app."
        menu.addItem(color)
        menu.addItem(shortcuts.menuItem(for: "keyboardShortcuts"))
        menu.addItem(.separator())
        menu.addItem(shortcuts.menuItem(for: "copyPageLink"))
        menu.addItem(shortcuts.menuItem(for: "openInBrowser"))
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
        menu.addItem(appDelegate.shortcuts.menuItem(for: "showHistory"))
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
        appDelegate.tabsDidChange()
    }

    /// This window's tabs and frame, to reopen at the next launch. nil if no tab has a page
    /// worth reopening.
    var savedTabs: SavedTabs.Window? {
        var pages: [URL] = []
        var selected = 0
        for tab in tabs {
            guard let page = tab.pageToReopen else { continue }
            if tab === selectedTab { selected = pages.count }
            pages.append(page)
        }
        guard !pages.isEmpty else { return nil }
        // The frame from before full screen; a reopened window starts out of full screen.
        let frame = isFullScreen || window?.styleMask.contains(.fullScreen) == true
            ? framesByScreenLayout[Self.screenLayout] : window?.frame
        return SavedTabs.Window(profile: profileID, tabs: pages, selected: selected, frame: frame)
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

    func windowDidResize(_ notification: Notification) {
        layoutTrafficLights()
        windowFrameDidChange()
    }
    func windowDidMove(_ notification: Notification) { windowFrameDidChange() }
    func windowDidBecomeKey(_ notification: Notification) {
        layoutTrafficLights()
        appDelegate.profiles.lastUsed = profileID
        // The front window is saved first.
        appDelegate.tabsDidChange()
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
        isFullScreen = true
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        setStripRevealed(false, animated: true)
        startFullScreenMouseTracking()
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        stopFullScreenMouseTracking()
        isFullScreen = false
        setStripRevealed(true, animated: false)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        tabStrip.leadingInset = Self.stripInsetForTrafficLights
        layoutTrafficLights()
    }

    // MARK: - Full screen tab strip auto-hide

    /// In full screen the tab strip hides so the page can use the whole screen. Moving the
    /// mouse to the top edge reveals it again; moving away hides it after a short delay.
    private func startFullScreenMouseTracking() {
        stopFullScreenMouseTracking()
        fullScreenMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleFullScreenMouseMoved()
            return event
        }
    }

    private func stopFullScreenMouseTracking() {
        hideStripWorkItem?.cancel()
        hideStripWorkItem = nil
        if let fullScreenMouseMonitor {
            NSEvent.removeMonitor(fullScreenMouseMonitor)
            self.fullScreenMouseMonitor = nil
        }
    }

    private func handleFullScreenMouseMoved() {
        guard isFullScreen else { return }
        if isPointerOverStripOrRevealZone() || isAnyStripMenuOpen() {
            cancelHideStrip()
            if !isStripRevealed {
                setStripRevealed(true, animated: true)
            }
        } else if isStripRevealed {
            scheduleHideStrip()
        }
    }

    /// Distance of the pointer from the top of the content view, in points.
    private func pointerYFromTop() -> CGFloat? {
        guard let window, let contentView = window.contentView else { return nil }
        let location = window.mouseLocationOutsideOfEventStream
        let point = contentView.convert(location, from: nil)
        return contentView.bounds.height - point.y
    }

    private func isPointerOverStripOrRevealZone() -> Bool {
        guard let yFromTop = pointerYFromTop() else { return false }
        // While the strip is up (or still animating closed), keep it if the pointer is over it.
        let stripZone = max(stripHeightConstraint.constant, isStripRevealed ? Self.stripHeight : 0)
        if stripZone > 0 {
            return yFromTop <= stripZone
        }
        return yFromTop <= Self.fullScreenRevealHeight
    }

    private func isAnyStripMenuOpen() -> Bool {
        [profileButton, extensionsButton, moreButton].contains(where: \.isShowingMenu)
    }

    private func scheduleHideStrip() {
        guard isFullScreen, isStripRevealed, hideStripWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hideStripWorkItem = nil
            guard self.isFullScreen, self.isStripRevealed else { return }
            if self.isPointerOverStripOrRevealZone() || self.isAnyStripMenuOpen() { return }
            self.setStripRevealed(false, animated: true)
        }
        hideStripWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stripHideDelay, execute: work)
    }

    private func cancelHideStrip() {
        hideStripWorkItem?.cancel()
        hideStripWorkItem = nil
    }

    private func setStripRevealed(_ revealed: Bool, animated: Bool) {
        let targetHeight: CGFloat = revealed ? Self.stripHeight : 0
        let targetAlpha: CGFloat = revealed ? 1 : 0
        guard isStripRevealed != revealed
                || stripHeightConstraint.constant != targetHeight
                || tabStrip.alphaValue != targetAlpha
        else { return }
        isStripRevealed = revealed
        cancelHideStrip()
        let apply = {
            self.stripHeightConstraint.constant = targetHeight
            self.tabStrip.alphaValue = targetAlpha
            // Keep hit-testing off while collapsed so clicks reach the page underneath.
            self.tabStrip.isHidden = !revealed
            self.window?.contentView?.layoutSubtreeIfNeeded()
        }
        if animated, window?.contentView != nil {
            // Unhide before animating in so the fade/slide is visible.
            if revealed { tabStrip.isHidden = false }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                context.allowsImplicitAnimation = true
                self.stripHeightConstraint.animator().constant = targetHeight
                self.tabStrip.animator().alphaValue = targetAlpha
                self.window?.contentView?.layoutSubtreeIfNeeded()
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.tabStrip.isHidden = !revealed
                    self.tabStrip.alphaValue = targetAlpha
                }
            })
        } else {
            apply()
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        layoutTrafficLights()
    }

    func windowWillClose(_ notification: Notification) {
        // Before the tabs go, in case this is the last window and the app is quitting.
        appDelegate.windowWillClose(self)
        stopFullScreenMouseTracking()
        stopObservingSleepAndWake()
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

    /// New windows use this window's profile.
    @objc func newWindow(_ sender: Any?) {
        appDelegate.openWindow(profile: profileID)
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

    /// Hard Reload: the page and everything on it from the server, skipping the cache.
    @objc func reloadIgnoringCache(_ sender: Any?) {
        selectedTab?.hardReload()
    }

    // MARK: - Find

    /// Shows the Find box (⌘F), or selects its text if it's already open.
    @objc func showFind(_ sender: Any?) {
        findBar.isHidden = false
        window?.makeFirstResponder(findBar.field)
        findBar.field.selectText(nil)
        if !findBar.query.isEmpty { runFind(backwards: false, fromStart: true) }
    }

    @objc func findNext(_ sender: Any?) {
        guard !findBar.query.isEmpty else { return showFind(sender) }
        findBar.isHidden = false
        runFind(backwards: false, fromStart: false)
    }

    @objc func findPrevious(_ sender: Any?) {
        guard !findBar.query.isEmpty else { return showFind(sender) }
        findBar.isHidden = false
        runFind(backwards: true, fromStart: false)
    }

    private func runFind(backwards: Bool, fromStart: Bool) {
        guard let tab = selectedTab else { return }
        let query = findBar.query
        guard !query.isEmpty else {
            tab.endFind()
            findBar.showResult(nil)
            return
        }
        tab.find(query, backwards: backwards, fromStart: fromStart) { [weak self] found, count in
            // Ignore results for a query that has since changed, or a tab no longer shown.
            guard let self, self.findBar.query == query, self.selectedTab === tab else { return }
            if !found {
                self.findBar.showResult("Not found")
            } else {
                self.findBar.showResult(count > 1 ? "\(count) matches" : count == 1 ? "1 match" : nil)
            }
        }
    }

    private func closeFind() {
        findBar.isHidden = true
        findBar.showResult(nil)
        tabs.forEach { $0.endFind() }
        if let tab = selectedTab { window?.makeFirstResponder(tab.webView) }
    }

    /// Takes keys nothing else did, so they don't beep. Web pages pass up keys they don't use,
    /// such as the arrow keys on a page that can't scroll, and this controller is the last
    /// responder they reach. Browsers stay quiet.
    override func keyDown(with event: NSEvent) {}

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
