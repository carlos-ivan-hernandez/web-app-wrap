import AppKit
@preconcurrency import WebKit
import WebAppWrapKit

/// One tab: a web view plus the policies for where its links go.
/// The owning BrowserWindowController shows it and draws its entry in the tab strip.
final class Tab: NSObject, WKNavigationDelegate, WKUIDelegate {
    private static let zoomSteps: [CGFloat] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    let webView: WKWebView
    weak var host: BrowserWindowController?
    private unowned let appDelegate: AppDelegate
    private let policy: LinkPolicy
    private var observations: [NSKeyValueObservation] = []
    private var lastFailedURL: URL?

    /// True until the tab has shown its first page. A fresh tab never spawns further
    /// tabs, and is closed if its only job turned out to be a download or a browser hand-off.
    private var isFresh: Bool { webView.backForwardList.currentItem == nil }

    init(appDelegate: AppDelegate, policy: LinkPolicy, configuration: WKWebViewConfiguration) {
        self.appDelegate = appDelegate
        self.policy = policy
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.pageZoom = appDelegate.pageZoom
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

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
        appDelegate.history.recordVisit(url: webView.url, title: webView.title)
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
        appDelegate.history.recordVisit(url: webView.url, title: webView.title)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
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

        let background = action.modifierFlags.contains(.command) && !action.modifierFlags.contains(.shift)
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
