import AppKit
@preconcurrency import WebKit
import WebAppWrapKit

/// One tab: a web view plus the policies for where its links go.
/// The owning BrowserWindowController shows it and draws its entry in the tab strip.
final class Tab: NSObject, WKNavigationDelegate, WKUIDelegate {
    private static let zoomSteps: [CGFloat] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    let webView: TabWebView
    weak var host: BrowserWindowController?
    private unowned let appDelegate: AppDelegate
    /// Read fresh each time, so changes to Allowed Sites apply to open tabs.
    private var policy: LinkPolicy { appDelegate.linkPolicy }
    private var observations: [NSKeyValueObservation] = []
    private var lastFailedURL: URL?
    /// True while the web view is transparent, before its first page has painted. The window
    /// behind it is the title bar color, so a new tab never flashes white.
    private var isWaitingForFirstPaint = false
    /// Set when the right-click menu's Open Link in New Tab is chosen, until WebKit asks for
    /// the new tab, so it opens in the background as in Safari and Chrome.
    private var opensNextNewTabInBackground = false

    /// True until the tab has shown its first page. A fresh tab never spawns further
    /// tabs, and is closed if its only job turned out to be a download or a browser hand-off.
    private var isFresh: Bool { webView.backForwardList.currentItem == nil }

    init(appDelegate: AppDelegate, configuration: WKWebViewConfiguration) {
        self.appDelegate = appDelegate
        self.webView = TabWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        super.init()
        webView.onOpenInNewTab = { [weak self] in
            guard let self else { return }
            self.opensNextNewTabInBackground = true
            // In case WebKit never asks (e.g. the link was blocked).
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.opensNextNewTabInBackground = false
            }
        }

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.pageZoom = appDelegate.pageZoom
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        setDrawsBackground(false)

        // KVO calls these on the main thread, outside the main actor's knowledge.
        let onChange: (@escaping @MainActor (Tab) -> Void) -> (Any, Any) -> Void = { [weak self] action in
            { _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    action(self)
                }
            }
        }
        let titleChanged = onChange { tab in
            tab.host?.tabDidChange(tab)
            tab.historyTitleDidChange()
        }
        let loadingChanged = onChange { tab in tab.host?.tabDidChange(tab) }
        let urlChanged = onChange { tab in
            tab.host?.tabDidChange(tab)
            tab.urlDidChange()
        }
        observations = [
            webView.observe(\.title) { titleChanged($0, $1) },
            webView.observe(\.isLoading) { loadingChanged($0, $1) },
            webView.observe(\.url) { urlChanged($0, $1) },
        ]
    }

    var displayTitle: String {
        let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return title }
        return webView.url?.host ?? "New Tab"
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    /// Called when the tab is removed. Stops everything so the web view can be released.
    func tearDown() {
        observations = []
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    private func openInBrowser(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func closeIfFresh() {
        guard isFresh else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.host?.closeTab(self)
        }
    }

    // MARK: - History

    /// Full page loads are recorded when they commit (see didCommit). An address change while
    /// nothing is loading is a single-page app moving to another page, so it's a visit too.
    private func urlDidChange() {
        guard !webView.isLoading else { return }
        recordVisit()
    }

    /// Only pages on the app's own or allowed sites are kept, not sign-in pages on others.
    private func recordVisit() {
        guard let url = webView.url, policy.isInternal(url) else { return }
        appDelegate.history.recordVisit(url: url, title: webView.title)
        if policy.allowsAllSites, !policy.isListed(url) {
            appDelegate.allowedSites.noteVisited(url)
        }
    }

    private func historyTitleDidChange() {
        appDelegate.history.updateTitle(webView.title, for: webView.url)
    }

    // MARK: - Page commands

    func reload() {
        if let lastFailedURL, webView.url == nil || webView.url?.scheme == "about" {
            load(lastFailedURL)
        } else {
            webView.reload()
        }
    }

    /// Reloads the page and everything on it from the server, skipping the cache.
    func hardReload() {
        if let lastFailedURL, webView.url == nil || webView.url?.scheme == "about" {
            webView.load(URLRequest(url: lastFailedURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
        } else {
            webView.reloadFromOrigin()
        }
    }

    // MARK: - Find

    /// Finds `text` on the page, after the current match or before it with `backwards`.
    /// `fromStart` searches from the start of the current match, for a query that changed.
    func find(_ text: String, backwards: Bool, fromStart: Bool, completion: @escaping (_ found: Bool, _ count: Int) -> Void) {
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        let search = { [weak self] in
            guard let self else { return }
            self.webView.find(text, configuration: configuration) { [weak self] result in
                guard let self else { return }
                guard result.matchFound else {
                    self.runFindScript(Self.clearHighlightScript)
                    completion(false, 0)
                    return
                }
                self.runFindScript(Self.highlightScript, arguments: ["text": text]) { count in
                    completion(true, count)
                }
            }
        }
        if fromStart {
            runFindScript("const s = getSelection(); if (s.rangeCount) s.collapseToStart(); return 0") { _ in search() }
        } else {
            search()
        }
    }

    /// Removes the highlight of the current match.
    func endFind() {
        runFindScript(Self.clearHighlightScript)
    }

    /// Runs in a separate JavaScript world, so the page's scripts can't interfere. Returns
    /// the script's number, or 0.
    private func runFindScript(_ script: String, arguments: [String: Any] = [:], completion: ((Int) -> Void)? = nil) {
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .defaultClient) { result in
            let number = (try? result.get()) as? NSNumber
            completion?(number?.intValue ?? 0)
        }
    }

    /// WebKit selects the match, which shows in gray while the Find box has focus. This
    /// marks it in yellow, like Safari, and returns how many matches the page's text has.
    private static let highlightScript = """
        if (window.CSS && CSS.highlights && window.Highlight) {
            if (!document.getElementById("webappwrap-find-style")) {
                const style = document.createElement("style");
                style.id = "webappwrap-find-style";
                style.textContent = "::highlight(webappwrap-find) { background-color: #FFE352; color: black; }";
                (document.head || document.documentElement).appendChild(style);
            }
            const selection = getSelection();
            if (selection.rangeCount) {
                CSS.highlights.set("webappwrap-find", new Highlight(selection.getRangeAt(0).cloneRange()));
            }
        }
        const haystack = (document.body ? document.body.innerText : "").toLocaleLowerCase();
        const needle = text.toLocaleLowerCase();
        let count = 0;
        for (let at = haystack.indexOf(needle); needle && at !== -1; at = haystack.indexOf(needle, at + needle.length)) {
            count++;
        }
        return count;
        """

    private static let clearHighlightScript = """
        if (window.CSS && CSS.highlights) CSS.highlights.delete("webappwrap-find");
        document.getElementById("webappwrap-find-style")?.remove();
        return 0;
        """

    func zoomIn() {
        setZoom(Self.zoomSteps.first { $0 > webView.pageZoom + 0.001 } ?? Self.zoomSteps.last!)
    }

    func zoomOut() {
        setZoom(Self.zoomSteps.last { $0 < webView.pageZoom - 0.001 } ?? Self.zoomSteps.first!)
    }

    func resetZoom() {
        setZoom(1)
    }

    private func setZoom(_ zoom: CGFloat) {
        webView.pageZoom = zoom
        appDelegate.pageZoom = zoom
    }

    /// WKWebView has no public call to open Web Inspector, so this uses its private inspector
    /// object, checking each step so a future WebKit change makes it a no-op rather than a crash.
    func showWebInspector() {
        guard webView.responds(to: NSSelectorFromString("_inspector")),
              let inspector = webView.value(forKey: "_inspector") as? NSObject,
              inspector.responds(to: NSSelectorFromString("show"))
        else {
            NSSound.beep()
            return
        }
        inspector.perform(NSSelectorFromString("show"))
    }

    // MARK: - Navigation policy

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if action.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        guard let url = action.request.url else {
            decisionHandler(.allow)
            return
        }

        let destination = policy.destination(for: url)
        let opensNewWindow = action.targetFrame == nil
        let isMainFrame = action.targetFrame?.isMainFrame ?? false

        // Iframes can load anything on the web, but may not launch other apps.
        guard opensNewWindow || isMainFrame else {
            decisionHandler(destination == .system ? .cancel : .allow)
            return
        }

        if destination == .system {
            NSWorkspace.shared.open(url)
            closeIfFresh()
            decisionHandler(.cancel)
            return
        }

        // Only clicks are routed. Redirects and scripted navigations to other hosts stay in
        // the app so sign-in flows (SSO, OAuth) keep working.
        if action.navigationType == .linkActivated {
            if destination == .browser {
                openInBrowser(url)
                closeIfFresh()
                decisionHandler(.cancel)
                return
            }
            if action.modifierFlags.contains(.command) && !isFresh {
                // Like browsers: cmd+click opens in the background, cmd+shift+click brings it forward.
                host?.openTab(url: url, after: self, activate: action.modifierFlags.contains(.shift))
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor response: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if let http = response.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
           disposition.lowercased().hasPrefix("attachment") {
            decisionHandler(.download)
            return
        }
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = appDelegate.downloads
        closeIfFresh()
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = appDelegate.downloads
        closeIfFresh()
    }

    // MARK: - Load results

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        recordVisit()
        if isWaitingForFirstPaint { restoreBackgroundAfterFirstPaint() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        drawBackground()
        if webView.url?.scheme != "about" { lastFailedURL = nil }
        host?.tabDidChange(self)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        let ignorable = (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
            // 102: frame load interrupted (we cancelled it or it became a download); 204: handled by a plug-in.
            || (nsError.domain == "WebKitErrorDomain" && (nsError.code == 102 || nsError.code == 204))
        guard !ignorable else { return }

        let failingURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? appDelegate.config.baseURL
        lastFailedURL = failingURL
        webView.loadHTMLString(
            ErrorPage.html(title: "Can’t open this page", message: nsError.localizedDescription, retryURL: failingURL),
            baseURL: nil
        )
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        drawBackground()
    }

    // MARK: - First paint

    /// WebKit paints a white page until the first page draws. Turning that off shows the
    /// window's title bar color instead. There's no public switch for it on macOS, so this
    /// is skipped if WebKit ever drops the private one.
    private func setDrawsBackground(_ draws: Bool) {
        guard webView.responds(to: NSSelectorFromString("_setDrawsBackground:"))
            || webView.responds(to: NSSelectorFromString("setDrawsBackground:"))
        else { return }
        webView.setValue(draws, forKey: "drawsBackground")
        isWaitingForFirstPaint = !draws
    }

    /// Pages that set no background of their own rely on WebKit's white one, so it comes
    /// back once the page is about to paint: after its HTML and blocking styles have loaded
    /// and two animation frames have passed. didFinish and didFail also bring it back, for
    /// tabs in the background, where animation frames don't run.
    private func restoreBackgroundAfterFirstPaint() {
        let script = """
            if (document.readyState === "loading") {
                await new Promise(resolve => document.addEventListener("DOMContentLoaded", resolve, { once: true }));
            }
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            """
        // A separate JavaScript world, so the page's own scripts can't interfere.
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .defaultClient) { [weak self] result in
            // A failure means the page was replaced; its own commit or finish handles that.
            if case .success = result { self?.drawBackground() }
        }
    }

    private func drawBackground() {
        if isWaitingForFirstPaint { setDrawsBackground(true) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // MARK: - Location

    #if compiler(>=6.4)
    @available(macOS 27.0, *)
    func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        decisionHandler(appDelegate.location.allows(origin) ? .grant : .deny)
    }
    #endif

    /// Before macOS 27, WebKit asks through this unofficial method instead, and refuses
    /// location to every page if it's missing.
    @objc(_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:)
    func webViewRequestsLocation(
        _ webView: WKWebView,
        origin: WKSecurityOrigin,
        frame: WKFrameInfo,
        decisionHandler: @escaping (Bool) -> Void
    ) {
        decisionHandler(appDelegate.location.allows(origin))
    }

    // MARK: - New windows (target=_blank, window.open)

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = action.request.url, policy.destination(for: url) == .browser {
            // A scripted popup with a size (e.g. "Sign in with Google") needs its opener to
            // report back, so it stays in the app. Everything else external goes to the browser.
            let isAuthStylePopup = action.navigationType != .linkActivated && windowFeatures.width != nil
            if !isAuthStylePopup {
                openInBrowser(url)
                return nil
            }
        }
        guard let host else { return nil }

        let background = opensNextNewTabInBackground
            || (action.modifierFlags.contains(.command) && !action.modifierFlags.contains(.shift))
        opensNextNewTabInBackground = false
        return host.openTab(url: nil, configuration: configuration, after: self, activate: !background).webView
    }

    /// window.close() from the page.
    func webViewDidClose(_ webView: WKWebView) {
        host?.closeTab(self)
    }

    // MARK: - JavaScript panels and file pickers

    private func alertTitle(for frame: WKFrameInfo) -> String {
        frame.request.url?.host ?? appDelegate.config.appName
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = alertTitle(for: frame)
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        present(alert) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = alertTitle(for: frame)
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = alertTitle(for: frame)
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        present(alert) { completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil) }
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        if let window = host?.window {
            panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
        } else {
            completionHandler(panel.runModal() == .OK ? panel.urls : nil)
        }
    }

    /// Shows the alert as a sheet, first bringing this tab forward so it's clear who's asking.
    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let host, let window = host.window {
            host.select(self)
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}

/// A tab's web view. Its right-click menu opens links in a new tab, where WebKit's says
/// "New Window".
final class TabWebView: WKWebView {
    /// Called when Open Link (or Image, Video, Frame) in New Tab is chosen, just before
    /// WebKit opens it.
    var onOpenInNewTab: (() -> Void)?

    private static let newTabTitles = [
        "WKMenuItemIdentifierOpenLinkInNewWindow": "Open Link in New Tab",
        "WKMenuItemIdentifierOpenImageInNewWindow": "Open Image in New Tab",
        "WKMenuItemIdentifierOpenMediaInNewWindow": "Open Video in New Tab",
        "WKMenuItemIdentifierOpenFrameInNewWindow": "Open Frame in New Tab",
    ]

    /// WebKit's own target and action for the items above, while the menu is open.
    private var originalActions: [ObjectIdentifier: (target: AnyObject?, action: Selector?)] = [:]

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        originalActions = [:]
        for item in menu.items {
            guard let id = item.identifier?.rawValue, let title = Self.newTabTitles[id] else { continue }
            item.title = title
            // Pass through this view first, then on to WebKit's own action.
            originalActions[ObjectIdentifier(item)] = (item.target, item.action)
            item.target = self
            item.action = #selector(openInNewTab(_:))
        }
    }

    @objc private func openInNewTab(_ sender: NSMenuItem) {
        guard let original = originalActions[ObjectIdentifier(sender)], let action = original.action else { return }
        onOpenInNewTab?()
        NSApp.sendAction(action, to: original.target, from: sender)
    }
}
