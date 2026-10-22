import AppKit
import WebKit
import WebAppWrapKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }

    private static let windowAutosaveName = "WebAppWrapBrowserWindow"
    private static let pageZoomKey = "PageZoom"

    private(set) var config: WrapperConfig!
    let downloads = DownloadManager()
    /// Pages visited in this app, shown in the More menu and the History window.
    let history = HistoryController()
    private var historyWindow: HistoryWindowController?
    /// Sites besides the app's own that it may open (the ⋮ menu's Allowed Sites).
    let allowedSites = AllowedSites()
    private var allowedSitesWindow: AllowedSitesWindowController?
    /// Keyboard shortcuts for the menu commands, changeable from the ⋮ menu.
    let shortcuts = ShortcutStore()
    private var shortcutsWindow: ShortcutsWindowController?
    /// Sets of logins and site data; each window uses one.
    let profiles = Profiles()
    private var profilesWindow: ProfilesWindowController?
    /// Forwards the web app's notifications to macOS. Made before launch finishes (see
    /// applicationWillFinishLaunching).
    private(set) var notifications: NotificationBridge!

    /// Which links stay in the app: its own site and the allowed sites, as they are now.
    var linkPolicy: LinkPolicy {
        LinkPolicy(baseURL: config.baseURL, allowedDomains: allowedSites.domains, allowsAllSites: allowedSites.allowsAll)
    }

    /// The app's own site, for messages: "linear.app".
    var ownSite: String {
        LinkPolicy.domain(of: config.baseURL) ?? config.baseURL.absoluteString
    }
    private var windowControllers: [BrowserWindowController] = []
    /// An ExtensionHost on macOS 15.4 and later (stored untyped so the app still runs on older systems).
    private var extensionHostStorage: AnyObject?
    /// Kept here because a menu doesn't retain its delegate.
    private var extensionsMenu: ExtensionsMenuController?

    // Extension support needs the macOS 15.4 SDK, which comes with Xcode 16.3 and Swift 6.1.
    // Older Xcode versions build the app without it.
    #if compiler(>=6.1)
    @available(macOS 15.4, *)
    var extensionHost: ExtensionHost? { extensionHostStorage as? ExtensionHost }
    #endif

    /// Last zoom level the user picked; applied to new tabs.
    var pageZoom: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: Self.pageZoomKey)
            return stored > 0 ? stored : 1
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: Self.pageZoomKey) }
    }

    // MARK: - App lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        notifications = NotificationBridge(appDelegate: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let config = WrapperConfig.load() else {
            let alert = NSAlert()
            alert.messageText = "This app has no web address configured."
            alert.informativeText = "Recreate it with WebAppWrap, or pass --url <address> when running the runtime directly."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        self.config = config
        // Tabs are drawn by BrowserWindowController, so turn off AppKit's own window tabbing
        // (and the menu items it would add).
        NSWindow.allowsAutomaticWindowTabbing = false
        let extensionsMenu = ExtensionsMenuController(appDelegate: self)
        self.extensionsMenu = extensionsMenu
        installMainMenu()
        shortcuts.onChange = { [weak self] in self?.installMainMenu() }
        profiles.onChange = { [weak self] in
            self?.windowControllers.forEach { $0.refreshProfile() }
        }

        #if compiler(>=6.1)
        if #available(macOS 15.4, *) {
            let host = ExtensionHost(appDelegate: self)
            extensionHostStorage = host
            host.onChange = { [weak self] in self?.extensionsDidChange() }
            // Load extensions before the first page so their content scripts run on it, but
            // don't keep the window waiting on a slow one.
            Task {
                await host.sync()
                self.openFirstWindow()
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.openFirstWindow()
            }
        } else {
            openFirstWindow()
        }
        #else
        openFirstWindow()
        #endif
    }

    private func installMainMenu() {
        guard let config, let extensionsMenu else { return }
        MainMenu.install(appName: config.appName, extensionsMenuDelegate: extensionsMenu, shortcuts: shortcuts)
    }

    private var hasOpenedFirstWindow = false

    private func openFirstWindow() {
        guard !hasOpenedFirstWindow else { return }
        hasOpenedFirstWindow = true
        openWindow(profile: profiles.lastUsed)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Picks up extension changes made in WebAppWrap (or another app) since the last look.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard hasOpenedFirstWindow else { return }
        // Notifications may have been allowed or turned off in System Settings.
        notifications.refreshSystemStatus()
        #if compiler(>=6.1)
        if #available(macOS 15.4, *), let host = extensionHost {
            Task { await host.sync() }
        }
        #endif
    }

    private func extensionsDidChange() {
        windowControllers.forEach { $0.refreshExtensionToolbar() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        history.saveNow()
    }

    /// Closing the last tab (cmd+W) quits the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Windows

    /// A new tab's settings. `profile` picks its cookies and site data.
    func makeWebViewConfiguration(profile: UUID) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = profiles.dataStore(for: profile)
        // Shared by all tabs; it carries the script that forwards notifications.
        configuration.userContentController = notifications.userContentController
        // Identify as Safari; some sites refuse sign-in from "embedded" browsers.
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences.isElementFullscreenEnabled = true
        #if compiler(>=6.1)
        if #available(macOS 15.4, *), let host = extensionHost {
            configuration.webExtensionController = host.controller
        }
        #endif
        // Adds "Inspect Element" to the right-click menu. There's no public API for this; the
        // key has been stable in WebKit for years, and is skipped if it ever disappears.
        if configuration.preferences.responds(to: NSSelectorFromString("_developerExtrasEnabled")) {
            configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }
        return configuration
    }

    /// Opens a window with one tab at `url` (the base URL by default), in `profile` (by
    /// default the front window's).
    @discardableResult
    func openWindow(url: URL? = nil, profile: UUID? = nil) -> BrowserWindowController {
        let profile = profile ?? frontWindowController?.profileID ?? profiles.lastUsed
        let controller = BrowserWindowController(appDelegate: self, profileID: profile)
        windowControllers.append(controller)
        #if compiler(>=6.1)
        if #available(macOS 15.4, *) {
            extensionHost?.controller.didOpenWindow(controller)
        }
        #endif
        if let window = controller.window { positionNewWindow(window) }
        controller.showWindow(nil)
        controller.openTab(url: url ?? config.baseURL)
        return controller
    }

    private func positionNewWindow(_ window: NSWindow) {
        let others = windowControllers.compactMap(\.window).filter { $0 !== window && $0.isVisible }
        if let reference = NSApp.keyWindow ?? others.last {
            window.setFrame(reference.frame.offsetBy(dx: 24, dy: -24), display: false)
        } else {
            if !window.setFrameUsingName(Self.windowAutosaveName) {
                if let screen = NSScreen.main?.visibleFrame {
                    let size = NSSize(width: min(1280, screen.width * 0.85), height: min(860, screen.height * 0.85))
                    window.setContentSize(size)
                }
                window.center()
            }
            window.setFrameAutosaveName(Self.windowAutosaveName)
        }
    }

    func windowDidClose(_ controller: BrowserWindowController) {
        windowControllers.removeAll { $0 === controller }
    }

    /// Open windows, frontmost first.
    var orderedWindowControllers: [BrowserWindowController] {
        let ordered = NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }
        return ordered.filter { controller in windowControllers.contains { $0 === controller } }
            + windowControllers.filter { controller in !ordered.contains { $0 === controller } }
    }

    var frontWindowController: BrowserWindowController? {
        (NSApp.keyWindow?.windowController as? BrowserWindowController) ?? orderedWindowControllers.first
    }

    /// The window and tab showing `webView`.
    func windowAndTab(for webView: WKWebView) -> (window: BrowserWindowController, tab: Tab)? {
        for controller in windowControllers {
            if let tab = controller.tabs.first(where: { $0.webView === webView }) {
                return (controller, tab)
            }
        }
        return nil
    }

    // MARK: - Actions that work even with no window open

    @objc func newWindow(_ sender: Any?) {
        openWindow()
    }

    @objc func newTab(_ sender: Any?) {
        openWindow()
    }

    /// The History window. Opening a page from it adds a tab to the front browser window.
    @objc func showHistory(_ sender: Any?) {
        if historyWindow == nil {
            historyWindow = HistoryWindowController(history: history, appName: config.appName) { [weak self] url in
                guard let self else { return }
                guard self.linkPolicy.isInternal(url) else {
                    self.explainBlocked(url)
                    return
                }
                if let controller = self.frontWindowController {
                    controller.openTab(url: url)
                    controller.showWindow(nil)
                } else {
                    self.openWindow(url: url)
                }
            }
        }
        historyWindow?.showWindow(nil)
    }

    /// Turns Allow All Sites on or off (⋮ menu).
    @objc func toggleAllowAllSites(_ sender: Any?) {
        allowedSites.allowsAll.toggle()
    }

    /// The Allowed Sites window.
    @objc func showAllowedSites(_ sender: Any?) {
        if allowedSitesWindow == nil {
            allowedSitesWindow = AllowedSitesWindowController(sites: allowedSites, appName: config.appName, ownSite: ownSite)
        }
        allowedSitesWindow?.showWindow(nil)
    }

    /// The Keyboard Shortcuts window (⋮ menu, and the app menu).
    @objc func showKeyboardShortcuts(_ sender: Any?) {
        if shortcutsWindow == nil {
            shortcutsWindow = ShortcutsWindowController(store: shortcuts, appName: config.appName)
        }
        shortcutsWindow?.showWindow(nil)
    }

    // MARK: - Notifications

    /// Turns notifications on or off (⋮ menu). Turning them on asks macOS for permission the
    /// first time, and points to System Settings if they're turned off there.
    @objc func toggleNotifications(_ sender: Any?) {
        if notifications.isEnabled && notifications.isAllowedBySystem {
            notifications.isEnabled = false
            return
        }
        notifications.isEnabled = true
        notifications.requestSystemPermission { [weak self] allowed in
            guard let self, !allowed else { return }
            let alert = NSAlert()
            alert.messageText = "Notifications for \(self.config.appName) are turned off in System Settings"
            alert.informativeText = "To get the site’s notifications, allow them for \(self.config.appName) in System Settings → Notifications."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                self.notifications.openSystemSettings()
            }
        }
    }

    // MARK: - Profiles

    /// Brings forward the front window using `profile`, or opens one.
    func showProfile(_ profile: UUID) {
        if let existing = orderedWindowControllers.first(where: { $0.profileID == profile }) {
            existing.showWindow(nil)
        } else {
            openWindow(profile: profile)
        }
    }

    /// Asks for a name, makes the profile and opens a window in it.
    @objc func newProfile(_ sender: Any?) {
        guard Profiles.isSupported else {
            let alert = NSAlert()
            alert.messageText = "Profiles need macOS 14 or later"
            alert.informativeText = "On this Mac, \(config.appName) can only use one set of logins."
            alert.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = "New Profile"
        alert.informativeText = "A profile has its own logins and site data, so you can use another account in its windows."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = profiles.uniqueName("Profile \(profiles.list.count + 1)")
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let profile = profiles.add(named: field.stringValue)
        openWindow(profile: profile.id)
    }

    /// The Manage Profiles window.
    @objc func showProfiles(_ sender: Any?) {
        if profilesWindow == nil {
            profilesWindow = ProfilesWindowController(appDelegate: self)
        }
        profilesWindow?.showWindow(nil)
    }

    /// Deletes a profile and its logins after asking, closing its windows first.
    func confirmRemoveProfile(_ profile: UUID) {
        guard profile != Profiles.defaultID else { return }
        let name = profiles.name(of: profile)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete the profile “\(name)”?"
        alert.informativeText = "Its windows close, and its logins, cookies and site data are deleted. This can’t be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let closing = windowControllers.filter { $0.profileID == profile }
        // Open a window first if none would be left, or closing the last one quits the app.
        if closing.count == windowControllers.count { openWindow(profile: Profiles.defaultID) }
        closing.forEach { $0.close() }
        if profiles.lastUsed == profile { profiles.lastUsed = Profiles.defaultID }
        profiles.remove(profile) { error in
            guard let error else { return }
            let failure = NSAlert()
            failure.messageText = "Some of “\(name)”’s site data couldn’t be deleted"
            failure.informativeText = error.localizedDescription
            failure.runModal()
        }
    }

    /// Says why a page from the history can't be opened.
    private func explainBlocked(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "\(LinkPolicy.domain(of: url) ?? "This site") isn’t allowed in \(config.appName)"
        alert.informativeText = "To open it here, add it to Allowed Sites in the ⋮ menu."
        alert.runModal()
    }
}
