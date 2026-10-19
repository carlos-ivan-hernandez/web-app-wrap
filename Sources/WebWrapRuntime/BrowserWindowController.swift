import AppKit
import WebKit
import WebWrapKit

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
        // AppKit re-lays out the title bar on resize, focus and appearance changes; put the buttons back each time.
        tabStrip.onLayout = { [weak self] in self?.layoutTrafficLights() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Tabs

    /// Adds a tab. Link-opened tabs go right after their opener; others go at the end.
    /// Pass `url: nil` with WebKit's `configuration` when WebKit itself will load the page.
    @discardableResult
    func openTab(url: URL?, configuration: WKWebViewConfiguration? = nil, after opener: Tab? = nil, activate: Bool = true) -> Tab {
        let tab = Tab(
            appDelegate: appDelegate,
            policy: appDelegate.config.policy,
            configuration: configuration ?? appDelegate.makeWebViewConfiguration()
        )
        tab.host = self
        // Lay the page out at the real size even while it loads in the background.
        tab.webView.frame = contentContainer.bounds
        tab.webView.autoresizingMask = [.width, .height]

        let index = opener.flatMap { tabs.firstIndex(of: $0) }.map { $0 + 1 } ?? tabs.count
        tabs.insert(tab, at: index)

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
            selectedTab?.webView.removeFromSuperview()
            tab.webView.frame = contentContainer.bounds
            contentContainer.addSubview(tab.webView)
            selectedTab = tab
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
        tab.tearDown()
        if selectedTab === tab {
            selectedTab = nil
            select(tabs[min(index, tabs.count - 1)])
        } else {
            refreshStrip()
        }
    }

    func tabDidChange(_ tab: Tab) {
        if tab === selectedTab {
            window?.title = tab.displayTitle
        }
        refreshStrip()
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
    private func layoutTrafficLights() {
        guard let window, !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let minimize = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let titlebar = close.superview,
              let titlebarContainer = titlebar.superview
        else { return }

        let height = Self.stripHeight
        let containerFrame = NSRect(x: 0, y: window.frame.height - height, width: window.frame.width, height: height)
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
    func windowDidBecomeKey(_ notification: Notification) { layoutTrafficLights() }
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
