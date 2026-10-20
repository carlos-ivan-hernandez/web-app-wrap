import AppKit
import WebKit

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
        MainMenu.install(appName: config.appName, extensionsMenuDelegate: extensionsMenu)

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

    private var hasOpenedFirstWindow = false

    private func openFirstWindow() {
        guard !hasOpenedFirstWindow else { return }
        hasOpenedFirstWindow = true
        openWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Picks up extension changes made in WebAppWrap (or another app) since the last look.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard hasOpenedFirstWindow else { return }
        #if compiler(>=6.1)
        if #available(macOS 15.4, *), let host = extensionHost {
            Task { await host.sync() }
        }
        #endif
    }

    private func extensionsDidChange() {
        windowControllers.forEach { $0.refreshExtensionToolbar() }
    }

    /// Closing the last tab (cmd+W) quits the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Windows

    func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
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

    /// Opens a window with one tab at `url` (the base URL by default).
    @discardableResult
    func openWindow(url: URL? = nil) -> BrowserWindowController {
        let controller = BrowserWindowController(appDelegate: self)
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

    // MARK: - Actions that work even with no window open

    @objc func newWindow(_ sender: Any?) {
        openWindow()
    }

    @objc func newTab(_ sender: Any?) {
        openWindow()
    }
}
