import AppKit
@preconcurrency import WebKit

// How tabs and windows look to browser extensions. With these, extension APIs such as
// tabs.query, tabs.update, windows.getCurrent and the activeTab permission work against the
// app's real tabs and windows. Every method is optional; WebKit fills in the rest.

@available(macOS 15.4, *)
@MainActor
extension Tab: WKWebExtensionTab {
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        host
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        host?.tabs.firstIndex(of: self) ?? NSNotFound
    }

    func title(for context: WKWebExtensionContext) -> String? {
        webView.title
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        webView.url
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        self.webView
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        !webView.isLoading
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        host?.selectedTab === self
    }

    func zoomFactor(for context: WKWebExtensionContext) -> Double {
        Double(webView.pageZoom)
    }

    func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        webView.pageZoom = CGFloat(zoomFactor)
        completionHandler(nil)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        load(url)
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if fromOrigin { webView.reloadFromOrigin() } else { reload() }
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        webView.goBack()
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        webView.goForward()
        completionHandler(nil)
    }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        host?.select(self)
        host?.window?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }

    func setSelected(_ selected: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if selected { host?.select(self) }
        completionHandler(nil)
    }

    func duplicate(
        using configuration: WKWebExtension.TabConfiguration,
        for context: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        let copy = host?.openTab(url: webView.url, after: self, activate: configuration.shouldBeActive)
        completionHandler(copy, nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        host?.closeTab(self)
        completionHandler(nil)
    }

    /// Clicking an extension's button gives it access to the current page (the activeTab permission).
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool {
        true
    }
}

@available(macOS 15.4, *)
@MainActor
extension BrowserWindowController: WKWebExtensionWindow {
    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        self.tabs.map { $0 as any WKWebExtensionTab }
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        selectedTab
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window else { return .normal }
        if window.isMiniaturized { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        if window.isZoomed { return .maximized }
        return .normal
    }

    func setWindowState(
        _ state: WKWebExtension.WindowState,
        for context: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let window else {
            completionHandler(nil)
            return
        }
        let isFullScreen = window.styleMask.contains(.fullScreen)
        switch state {
        case .minimized:
            window.miniaturize(nil)
        case .maximized:
            if window.isMiniaturized { window.deminiaturize(nil) }
            if !window.isZoomed { window.zoom(nil) }
        case .fullscreen:
            if !isFullScreen { window.toggleFullScreen(nil) }
        case .normal:
            if window.isMiniaturized { window.deminiaturize(nil) }
            if isFullScreen { window.toggleFullScreen(nil) }
        @unknown default:
            break
        }
        completionHandler(nil)
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        false
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        window?.frame ?? .null
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        window?.screen?.frame ?? .null
    }

    func setFrame(_ frame: CGRect, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        window?.setFrame(frame, display: true)
        completionHandler(nil)
    }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        window?.close()
        completionHandler(nil)
    }
}

/// An extension's button in the tab bar, with its badge (such as a count of blocked items).
final class ExtensionToolbarButton: NSButton {
    var onClick: (() -> Void)?
    var badgeText = "" {
        didSet { if badgeText != oldValue { needsDisplay = true } }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        isBordered = false
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        target = self
        action = #selector(clicked)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var mouseDownCanMoveWindow: Bool { false }

    @objc private func clicked() {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !badgeText.isEmpty else { return }
        let text = String(badgeText.prefix(4)) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let badge = NSRect(
            x: bounds.maxX - size.width - 6, y: bounds.minY + 1,
            width: size.width + 6, height: size.height + 1
        )
        NSColor.systemRed.setFill()
        NSBezierPath(roundedRect: badge, xRadius: badge.height / 2, yRadius: badge.height / 2).fill()
        text.draw(at: NSPoint(x: badge.minX + 3, y: badge.minY + 0.5), withAttributes: attributes)
    }
}

/// The Extensions menu: each installed extension, whether it's on for this app, its toolbar
/// button and options page, and a way to manage extensions in WebAppWrap. Rebuilt each time
/// it opens.
@MainActor
final class ExtensionsMenuController: NSObject, NSMenuDelegate {
    private unowned let appDelegate: AppDelegate
    /// WebAppWrap's bundle ID (Support/Info.plist).
    private static let generatorBundleID = "com.waw.WebAppWrap"

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // Items are enabled or disabled here, not by the responder chain.
        menu.autoenablesItems = false
        if #available(macOS 15.4, *), let host = appDelegate.extensionHost {
            addExtensions(from: host, to: menu)
        } else {
            menu.addItem(disabled("Extensions need macOS 15.4 or later"))
        }
        menu.addItem(.separator())
        menu.addItem(item("Manage Extensions in WebAppWrap…") { [weak self] in self?.openGenerator() })
    }

    @available(macOS 15.4, *)
    private func addExtensions(from host: ExtensionHost, to menu: NSMenu) {
        guard !host.installed.isEmpty else {
            menu.addItem(disabled("No extensions installed"))
            return
        }
        let appID = appDelegate.config.appID
        for installed in host.installed {
            let context = host.context(for: installed.id)
            let entry = NSMenuItem(title: installed.name, action: nil, keyEquivalent: "")
            entry.state = context == nil ? .off : .on
            let submenu = NSMenu()
            submenu.autoenablesItems = false

            let isOn = installed.isEnabled(forApp: appID)
            let toggle = item(isOn ? "Turn Off for This App" : "Turn On for This App") {
                host.setEnabled(!isOn, extensionID: installed.id)
            }
            if appID == nil {
                toggle.isEnabled = false
                toggle.toolTip = "This app was made from the command line, so it uses each extension’s default. Rebuild it in WebAppWrap’s My Apps to choose per app."
            }
            submenu.addItem(toggle)

            if let context {
                let front = appDelegate.frontWindowController
                if context.action(for: front?.selectedTab) != nil {
                    submenu.addItem(item("Click Toolbar Button") {
                        context.performAction(for: front?.selectedTab)
                    })
                }
                if context.optionsPageURL != nil {
                    submenu.addItem(item("Options…") { host.openOptionsPage(context) })
                }
            } else if let failure = host.failures[installed.id] {
                submenu.addItem(.separator())
                submenu.addItem(disabled("Couldn’t load: \(failure)"))
            }
            entry.submenu = submenu
            menu.addItem(entry)
        }
    }

    private func openGenerator() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.generatorBundleID) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        return item
    }
}

/// A menu item that runs a closure, for menus built on the fly.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
