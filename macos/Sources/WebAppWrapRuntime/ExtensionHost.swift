import AppKit
@preconcurrency import WebKit
import WebAppWrapKit

// Needs the macOS 15.4 SDK (Xcode 16.3, Swift 6.1). See AppDelegate.
#if compiler(>=6.1)

/// Loads the browser extensions installed in WebAppWrap that are on for this app, and acts as
/// the browser they talk to: it lists windows and tabs, opens new ones, shows toolbar popups
/// and asks for extra permissions.
///
/// The list is in ~/Library/Application Support/WebAppWrap/extensions.json (see
/// ExtensionStore). It's read at launch and again whenever the app comes to the front, so
/// changes made in WebAppWrap apply without a rebuild.
@available(macOS 15.4, *)
@MainActor
final class ExtensionHost: NSObject, WKWebExtensionControllerDelegate {
    /// Shared by every tab's web view configuration. Its storage is this app's own.
    let controller: WKWebExtensionController = {
        let configuration = WKWebExtensionController.Configuration.default()
        // Extension pages (background, popups, options) identify as Safari, like the tabs. With
        // WebKit's plain user agent, Bitwarden can't tell which browser it's in and won't start.
        let pages = configuration.webViewConfiguration ?? WKWebViewConfiguration()
        pages.applicationNameForUserAgent = AppDelegate.userAgentApplicationName
        configuration.webViewConfiguration = pages
        return WKWebExtensionController(configuration: configuration)
    }()
    /// Runs extensions' keyboard shortcuts (the manifest's "commands").
    private var keyMonitor: Any?
    private unowned let appDelegate: AppDelegate
    private let store = ExtensionStore.standard

    struct Loaded {
        let installed: InstalledExtension
        let context: WKWebExtensionContext
        /// WebKit gives every extension an action, so the manifest says whether there's really
        /// a toolbar button to click.
        let hasToolbarButton: Bool
    }

    /// Loaded extensions, in the order of WebAppWrap's list.
    private(set) var loaded: [Loaded] = []
    /// Installed extensions that are on for this app but couldn't be loaded: ID -> reason.
    private(set) var failures: [String: String] = [:]
    /// Every installed extension, loaded or not, as of the last sync.
    private(set) var installed: [InstalledExtension] = []
    private var isSyncing = false
    private var needsAnotherSync = false

    /// Called when the set of loaded extensions or a toolbar button changes.
    var onChange: (() -> Void)?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
        controller.delegate = self
        // Before the menus see the key, so an extension's shortcut works in the browser
        // windows. Other windows (such as Keyboard Shortcuts, while recording) are left alone.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window?.windowController is BrowserWindowController else { return event }
            for item in self.loaded where item.context.performCommand(for: event) {
                return nil
            }
            return event
        }
    }

    // MARK: - Loading

    /// Loads extensions that are now on for this app and unloads ones that aren't, or that
    /// WebAppWrap updated to a new version.
    func sync() async {
        guard !isSyncing else {
            needsAnotherSync = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        repeat {
            needsAnotherSync = false
            let list = (try? store.load()) ?? []
            installed = list
            let wanted = list.filter { $0.isEnabled(forApp: appDelegate.config.appID) }

            for item in loaded where !wanted.contains(where: { $0.id == item.installed.id && $0.folder == item.installed.folder }) {
                try? controller.unload(item.context)
                loaded.removeAll { $0.context === item.context }
            }
            failures = failures.filter { id, _ in wanted.contains { $0.id == id } }

            for item in wanted where !loaded.contains(where: { $0.installed.id == item.id }) {
                do {
                    let context = try await load(item)
                    let manifest = try? ExtensionManifest.read(from: store.resourceURL(for: item))
                    loaded.append(Loaded(installed: item, context: context, hasToolbarButton: manifest?.hasToolbarButton ?? true))
                    failures[item.id] = nil
                } catch {
                    failures[item.id] = error.localizedDescription
                    NSLog("WebAppWrap: couldn’t load extension %@: %@", item.name, error.localizedDescription)
                }
            }
            let order = list.map(\.id)
            loaded.sort { (order.firstIndex(of: $0.installed.id) ?? 0) < (order.firstIndex(of: $1.installed.id) ?? 0) }
            onChange?()
        } while needsAnotherSync
    }

    private func load(_ item: InstalledExtension) async throws -> WKWebExtensionContext {
        let webExtension = try await WKWebExtension(resourceBaseURL: store.resourceURL(for: item))
        let context = WKWebExtensionContext(for: webExtension)
        // A stable identity, so the extension's storage survives relaunches and updates.
        context.uniqueIdentifier = item.id
        if let baseURL = URL(string: "webkit-extension://\(item.id)/") {
            context.baseURL = baseURL
        }
        context.isInspectable = true
        try controller.load(context)
        // Granted after loading: loading reads the context's saved state, which can replace
        // grants made before it. Changing grants on a loaded context also makes WebKit
        // re-check which content scripts to inject.
        grantInstallPermissions(for: item, webExtension: webExtension, in: context)
        restoreOptionalGrants(for: item.id, in: context)
        for error in webExtension.errors + context.errors {
            NSLog("WebAppWrap: extension %@: %@", item.name, error.localizedDescription)
        }
        return context
    }

    /// Installing in WebAppWrap granted what the extension asks for up front: its permissions,
    /// its host permissions and the sites its content scripts run on. WebKit's requested match
    /// patterns leave out content script matches, and without a grant for a site, scripts like
    /// Dark Reader's and Vimium's never run there.
    private func grantInstallPermissions(for item: InstalledExtension, webExtension: WKWebExtension, in context: WKWebExtensionContext) {
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        var patterns = webExtension.requestedPermissionMatchPatterns
        let manifest = try? ExtensionManifest.read(from: store.resourceURL(for: item))
        for host in manifest?.hostPermissions ?? [] {
            if let pattern = try? WKWebExtension.MatchPattern(string: host) {
                patterns.insert(pattern)
            }
        }
        for pattern in patterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        // Lets an extension call its desktop app even if it would ask first (Bitwarden does).
        // Only NativeAppStandIns answers, so this reaches nothing outside the app.
        if manifest?.optionalPermissions.contains("nativeMessaging") == true {
            context.setPermissionStatus(.grantedExplicitly, for: .nativeMessaging)
        }
    }

    /// WebKit's problems with a loaded extension, such as manifest keys it doesn't support.
    func problems(for id: String) -> [String] {
        guard let context = context(for: id) else { return [] }
        return (context.webExtension.errors + context.errors).map(\.localizedDescription)
    }

    /// Clicks an extension's toolbar button. If the extension has a popup and WebKit doesn't
    /// ask for it to be shown, it's shown here, so a click is never silently dropped.
    func performAction(_ context: WKWebExtensionContext, for tab: Tab?, anchor: NSView) {
        context.performAction(for: tab)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let action = context.action(for: tab), action.presentsPopup,
                  let popover = action.popupPopover, !popover.isShown, anchor.window != nil
            else { return }
            NSLog("WebAppWrap: showing %@'s popup directly", context.webExtension.displayName ?? context.uniqueIdentifier)
            popover.behavior = .transient
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }

    /// Clicks an extension's toolbar button in the front window, for extensions that open their
    /// own popup.
    func showPopup(for context: WKWebExtensionContext) {
        guard let window = appDelegate.frontWindowController,
              let anchor = window.toolbarButton(for: context.uniqueIdentifier)
        else { return }
        window.window?.makeKeyAndOrderFront(nil)
        performAction(context, for: window.selectedTab, anchor: anchor)
    }

    /// Turns an extension on or off for this app from the Extensions menu, saving the choice
    /// to the shared list so WebAppWrap shows it too.
    func setEnabled(_ enabled: Bool, extensionID: String) {
        guard let appID = appDelegate.config.appID else { return }
        _ = try? store.update(extensionID) { $0.setEnabled(enabled, forApp: appID) }
        Task { await sync() }
    }

    func context(for id: String) -> WKWebExtensionContext? {
        loaded.first { $0.installed.id == id }?.context
    }

    // MARK: - Optional permissions granted while running

    /// Permissions an extension asks for later (optional permissions) are remembered per app.
    private func grantsKey(_ id: String) -> String { "ExtensionGrants.\(id)" }

    private func rememberGrants(permissions: [String] = [], patterns: [String] = [], for context: WKWebExtensionContext) {
        let key = grantsKey(context.uniqueIdentifier)
        var saved = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        saved["permissions", default: []] += permissions
        saved["patterns", default: []] += patterns
        UserDefaults.standard.set(saved, forKey: key)
    }

    private func restoreOptionalGrants(for id: String, in context: WKWebExtensionContext) {
        let saved = UserDefaults.standard.dictionary(forKey: grantsKey(id)) as? [String: [String]] ?? [:]
        for raw in saved["permissions"] ?? [] {
            context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(rawValue: raw))
        }
        for raw in saved["patterns"] ?? [] {
            if let pattern = try? WKWebExtension.MatchPattern(string: raw) {
                context.setPermissionStatus(.grantedExplicitly, for: pattern)
            }
        }
    }

    /// Asks whether to allow an extension something extra. Returns true for Allow.
    private func ask(_ context: WKWebExtensionContext, _ what: [String]) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Allow “\(context.webExtension.displayName ?? context.uniqueIdentifier)” more access?"
        alert.informativeText = "It’s asking to:\n" + what.map { "• \($0)" }.joined(separator: "\n")
            + "\n\nThis applies to \(appDelegate.config.appName) only."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Windows and tabs (WKWebExtensionControllerDelegate)

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        appDelegate.orderedWindowControllers
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        appDelegate.frontWindowController
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        let window = (configuration.window as? BrowserWindowController)
            ?? appDelegate.frontWindowController
            ?? appDelegate.openWindow()
        let tab = window.openTab(
            url: configuration.url ?? appDelegate.config.baseURL,
            at: configuration.index,
            activate: configuration.shouldBeActive
        )
        completionHandler(tab, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        let urls = configuration.tabURLs
        let window = appDelegate.openWindow(url: urls.first)
        for url in urls.dropFirst() {
            window.openTab(url: url, activate: false)
        }
        completionHandler(window, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        openOptionsPage(extensionContext)
        completionHandler(nil)
    }

    func openOptionsPage(_ context: WKWebExtensionContext) {
        guard let url = context.optionsPageURL else { return }
        let window = appDelegate.frontWindowController ?? appDelegate.openWindow()
        window.openTab(url: url)
    }

    // MARK: - Permission prompts

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        let names = permissions.map(\.rawValue).sorted()
        guard ask(extensionContext, names.map { "use “\($0)”" }) else {
            completionHandler([], nil)
            return
        }
        rememberGrants(permissions: names, for: extensionContext)
        completionHandler(permissions, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        let patterns = matchPatterns.map(\.string).sorted()
        guard ask(extensionContext, patterns.map { "read and change \($0)" }) else {
            completionHandler([], nil)
            return
        }
        rememberGrants(patterns: patterns, for: extensionContext)
        completionHandler(matchPatterns, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        let hosts = Set(urls.compactMap(\.host)).sorted()
        guard ask(extensionContext, hosts.map { "read and change \($0)" }) else {
            completionHandler([], nil)
            return
        }
        rememberGrants(patterns: hosts.map { "*://\($0)/*" }, for: extensionContext)
        completionHandler(urls, nil)
    }

    // MARK: - Desktop apps (native messaging)

    func webExtensionController(
        _ controller: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        NativeAppStandIns.reply(to: message, for: applicationIdentifier, from: extensionContext, host: self, replyHandler: replyHandler)
    }

    // MARK: - Toolbar buttons

    /// Shows the popup under the extension's button in the front window.
    func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for context: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let popover = action.popupPopover,
              let window = appDelegate.frontWindowController,
              let anchor = window.toolbarButton(for: context.uniqueIdentifier)
        else {
            NSLog("WebAppWrap: no popup or toolbar button to show %@'s popup under", context.uniqueIdentifier)
            completionHandler(nil)
            return
        }
        guard !popover.isShown else {
            completionHandler(nil)
            return
        }
        popover.behavior = .transient
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        completionHandler(nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        didUpdate action: WKWebExtension.Action,
        forExtensionContext context: WKWebExtensionContext
    ) {
        onChange?()
    }
}
#endif
