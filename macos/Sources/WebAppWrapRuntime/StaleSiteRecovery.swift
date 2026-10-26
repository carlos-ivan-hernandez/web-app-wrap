import Foundation
@preconcurrency import WebKit
import WebAppWrapKit

/// Recovers tabs showing an old copy of a site.
///
/// After a site is updated, its service worker can go on serving the old page while the
/// scripts that page asks for are gone from the server. Sites that send every unknown path to
/// index.html answer with HTML, which WebKit refuses ("'text/html' is not a valid JavaScript
/// MIME type for module script …"), and the page stays broken until the site's stored data is
/// cleared.
///
/// A script in every page reports scripts from the page's own site that fail to load. If the
/// server confirms the script is gone, the site's service worker and caches are cleared and
/// the tab reloads from the network. Nothing is cleared when the check can't reach the server
/// (offline), and a site is recovered at most once a minute, so a site that's broken for
/// another reason doesn't reload in a loop.
final class StaleSiteRecovery: NSObject, WKScriptMessageHandler {
    private static let handlerName = "wawScriptFailed"
    private static let retryInterval: TimeInterval = 60
    /// What a stale service worker keeps: its registration, its Cache Storage, and HTTP caches.
    /// Cookies and local storage stay, so sign-ins aren't lost.
    private static let dataTypes: Set<String> = [
        WKWebsiteDataTypeServiceWorkerRegistrations,
        WKWebsiteDataTypeFetchCache,
        WKWebsiteDataTypeDiskCache,
        WKWebsiteDataTypeMemoryCache,
    ]

    private unowned let appDelegate: AppDelegate
    /// When each host was last checked or recovered.
    private var lastAttempt: [String: Date] = [:]
    /// No cache or cookies, so the check sees what the server has now.
    private let session = URLSession(configuration: .ephemeral)

    init(appDelegate: AppDelegate, userContentController: WKUserContentController) {
        self.appDelegate = appDelegate
        super.init()
        userContentController.add(self, name: Self.handlerName)
    }

    /// Adds the page script. Called again whenever the shared controller's scripts are replaced
    /// (see NotificationBridge.installScript).
    static func addScript(to userContentController: WKUserContentController) {
        userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let webView = message.webView,
              let body = message.body as? [String: Any],
              let pageURL = webView.url, let host = pageURL.host?.lowercased(),
              appDelegate.linkPolicy.isInternal(pageURL)
        else { return }
        let scriptURL = (body["script"] as? String).flatMap(URL.init(string:))
            ?? (body["message"] as? String).flatMap(StaleScript.scriptURL(inErrorMessage:))
        guard let scriptURL, scriptURL.host?.lowercased() == host else { return }
        if let last = lastAttempt[host], Date().timeIntervalSince(last) < Self.retryInterval { return }
        lastAttempt[host] = Date()

        checkIsMissing(scriptURL) { [weak self, weak webView] isMissing in
            guard let self, let webView else { return }
            guard isMissing else {
                // The script is there (or the server couldn't be reached): not an old page.
                self.lastAttempt[host] = nil
                return
            }
            self.recover(webView, host: host, page: pageURL)
        }
    }

    /// Asks the server for the script, skipping every cache. Calls back on the main thread.
    private func checkIsMissing(_ url: URL, completion: @escaping (Bool) -> Void) {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        session.dataTask(with: request) { _, response, _ in
            let isMissing = (response as? HTTPURLResponse).map {
                StaleScript.isMissing(statusCode: $0.statusCode, mimeType: $0.mimeType)
            } ?? false
            DispatchQueue.main.async { completion(isMissing) }
        }.resume()
    }

    /// Clears the site's service worker and caches, then reloads the tab from the network.
    private func recover(_ webView: WKWebView, host: String, page: URL) {
        let store = webView.configuration.websiteDataStore
        store.fetchDataRecords(ofTypes: Self.dataTypes) { [weak webView] records in
            let siteRecords = records.filter { StaleScript.record(named: $0.displayName, covers: host) }
            NSLog("WebAppWrap: %@ is showing an old copy of the site; clearing its service worker and caches", host)
            store.removeData(ofTypes: Self.dataTypes, for: siteRecords) {
                // Only if the tab is still on that site.
                guard let webView, webView.url?.host?.lowercased() == host else { return }
                webView.reloadFromOrigin()
            }
        }
    }

    /// Reports the page's own scripts that fail to load: a <script> whose file is missing (or
    /// came back as HTML), or a module loaded with import() that failed the same way. Each
    /// script is reported once per page.
    private static let script = #"""
    (() => {
      const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wawScriptFailed;
      if (!handler) return;
      const reported = new Set();
      const report = (body, key) => {
        if (reported.has(key)) return;
        reported.add(key);
        handler.postMessage(body);
      };
      window.addEventListener('error', event => {
        const target = event.target;
        if (!(target instanceof HTMLScriptElement) || !target.src) return;
        let url;
        try { url = new URL(target.src, location.href); } catch (e) { return; }
        if (url.origin !== location.origin) return;
        report({script: url.href}, url.href);
      }, true);
      window.addEventListener('unhandledrejection', event => {
        const message = String((event.reason && event.reason.message) || '');
        if (/MIME type/i.test(message) && message.includes(location.origin)) report({message}, message);
      });
    })();
    """#
}
