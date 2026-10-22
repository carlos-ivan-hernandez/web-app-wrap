import AppKit
@preconcurrency import UserNotifications
@preconcurrency import WebKit

/// Shows the web app's notifications as macOS notifications.
///
/// WKWebView doesn't support the web's Notification API, so a script in every page replaces
/// `window.Notification` (and `registration.showNotification`) with a version that sends each
/// notification here. Clicking one brings its tab forward and fires the page's `click` event,
/// so the site can open the message it was about.
///
/// The page sees permission as "granted" once macOS allows this app's notifications and they're
/// on in the ⋮ menu, "denied" if either is off, and "default" before macOS has been asked.
final class NotificationBridge: NSObject, WKScriptMessageHandler, UNUserNotificationCenterDelegate {
    private static let handlerName = "wawNotifications"
    private static let enabledKey = "NotificationsEnabled"

    /// Shared by every tab's web view, so permission changes reach all of them.
    let userContentController = WKUserContentController()
    private unowned let appDelegate: AppDelegate
    private var systemStatus: UNAuthorizationStatus = .notDetermined
    /// What each delivered notification came from: its web view and the page's ID for it.
    private var delivered: [String: (webView: WeakWebView, pageID: String)] = [:]

    private final class WeakWebView {
        weak var value: WKWebView?
        init(_ value: WKWebView) { self.value = value }
    }

    /// The notification center needs a real app bundle; the bare runtime binary has none.
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }

    /// Notifications are on in the ⋮ menu (the default).
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            permissionDidChange()
        }
    }

    /// macOS allows this app's notifications.
    var isAllowedBySystem: Bool {
        systemStatus == .authorized || systemStatus == .provisional
    }

    /// The value pages see as `Notification.permission`.
    private var pagePermission: String {
        guard isEnabled, center != nil else { return "denied" }
        switch systemStatus {
        case .authorized, .provisional: return "granted"
        case .notDetermined: return "default"
        default: return "denied"
        }
    }

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        super.init()
        userContentController.add(self, name: Self.handlerName)
        installScript()
        // Set before launch finishes, so a click on a notification that launched the app is delivered.
        center?.delegate = self
        refreshSystemStatus()
    }

    /// Picks up changes made in System Settings. Called when the app becomes active.
    func refreshSystemStatus(then completion: (() -> Void)? = nil) {
        guard let center else {
            completion?()
            return
        }
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                let changed = self.systemStatus != settings.authorizationStatus
                self.systemStatus = settings.authorizationStatus
                if changed { self.permissionDidChange() }
                completion?()
            }
        }
    }

    /// Asks macOS for permission if it hasn't been asked yet. Calls back with whether
    /// notifications can be shown.
    func requestSystemPermission(_ completion: @escaping (Bool) -> Void) {
        guard let center else {
            completion(false)
            return
        }
        refreshSystemStatus { [weak self] in
            guard let self else { return }
            guard self.systemStatus == .notDetermined else {
                completion(self.isAllowedBySystem)
                return
            }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                DispatchQueue.main.async {
                    self.refreshSystemStatus { completion(self.isAllowedBySystem) }
                }
            }
        }
    }

    /// Opens this app's page in System Settings → Notifications.
    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: - Pages

    private func installScript() {
        userContentController.removeAllUserScripts()
        let source = Self.script.replacingOccurrences(of: "__WAW_PERMISSION__", with: pagePermission)
        userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }

    /// New pages get the new permission from the script; open pages are told directly.
    private func permissionDidChange() {
        installScript()
        let permission = pagePermission
        for controller in appDelegate.orderedWindowControllers {
            for tab in controller.tabs {
                tab.webView.evaluateJavaScript("window.__wawNotifications && window.__wawNotifications.setPermission('\(permission)')", completionHandler: nil)
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String,
              let webView = message.webView
        else { return }
        switch type {
        case "show":
            show(body, from: webView, origin: message.frameInfo.securityOrigin)
        case "close":
            if let pageID = body["id"] as? String { close(pageID: pageID, from: webView) }
        case "requestPermission":
            let requestID = (body["requestID"] as? NSNumber)?.intValue ?? 0
            guard isEnabled else {
                resolvePermissionRequest(requestID, in: webView)
                return
            }
            requestSystemPermission { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                self.resolvePermissionRequest(requestID, in: webView)
            }
        default:
            break
        }
    }

    private func resolvePermissionRequest(_ requestID: Int, in webView: WKWebView) {
        webView.evaluateJavaScript("window.__wawNotifications && window.__wawNotifications.resolvePermission(\(requestID), '\(pagePermission)')", completionHandler: nil)
    }

    private func show(_ body: [String: Any], from webView: WKWebView, origin: WKSecurityOrigin) {
        guard pagePermission == "granted", let center, let pageID = body["id"] as? String else { return }
        let content = UNMutableNotificationContent()
        content.title = (body["title"] as? String) ?? ""
        content.body = (body["body"] as? String) ?? ""
        if (body["silent"] as? Bool) != true { content.sound = .default }

        // A notification with the same tag from the same site replaces the earlier one, as in browsers.
        let tag = (body["tag"] as? String) ?? ""
        let identifier = tag.isEmpty ? pageID : "tag:\(origin.protocol)://\(origin.host):\(origin.port)/\(tag)"
        delivered[identifier] = (WeakWebView(webView), pageID)
        pruneDelivered()

        let iconURL = (body["icon"] as? String).flatMap(URL.init(string:))
        Self.attachment(from: iconURL) { attachment in
            if let attachment { content.attachments = [attachment] }
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            center.add(request, withCompletionHandler: nil)
        }
    }

    private func close(pageID: String, from webView: WKWebView) {
        let identifiers = delivered.filter { $0.value.pageID == pageID && $0.value.webView.value === webView }.map(\.key)
        guard !identifiers.isEmpty else { return }
        identifiers.forEach { delivered.removeValue(forKey: $0) }
        center?.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Forgets notifications whose tab has closed.
    private func pruneDelivered() {
        delivered = delivered.filter { $0.value.webView.value != nil }
    }

    /// Downloads the notification's icon (a sender's photo, say) to show beside it. Gives up
    /// after a few seconds, so a slow icon doesn't hold the notification back for long.
    private static func attachment(from url: URL?, completion: @escaping (UNNotificationAttachment?) -> Void) {
        guard let url, ["http", "https", "data"].contains(url.scheme?.lowercased() ?? "") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        URLSession.shared.dataTask(with: request) { data, response, _ in
            var attachment: UNNotificationAttachment?
            if let data, !data.isEmpty, data.count < 5_000_000 {
                let ext: String
                switch response?.mimeType?.lowercased() {
                case "image/png": ext = "png"
                case "image/gif": ext = "gif"
                default: ext = "jpg"
                }
                let file = FileManager.default.temporaryDirectory
                    .appendingPathComponent("WebAppWrapNotificationIcon-\(UUID().uuidString).\(ext)")
                if (try? data.write(to: file)) != nil {
                    // The notification center moves the file into its own storage.
                    attachment = try? UNNotificationAttachment(identifier: "icon", url: file, options: nil)
                    if attachment == nil { try? FileManager.default.removeItem(at: file) }
                }
            }
            DispatchQueue.main.async { completion(attachment) }
        }.resume()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shows notifications even while the app is in front, as browsers do.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// A click brings the tab that sent the notification forward and tells the page.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let isClick = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        DispatchQueue.main.async { [weak self] in
            defer { completionHandler() }
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            guard isClick,
                  let entry = self.delivered.removeValue(forKey: identifier),
                  let webView = entry.webView.value,
                  let found = self.appDelegate.windowAndTab(for: webView)
            else { return }
            found.window.showWindow(nil)
            found.window.select(found.tab)
            let pageID = entry.pageID.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("window.__wawNotifications && window.__wawNotifications.click('\(pageID)')", completionHandler: nil)
        }
    }

    // MARK: - The page script

    /// Replaces the page's Notification API. `__WAW_PERMISSION__` is filled in with the
    /// current permission.
    private static let script = #"""
    (() => {
      if (window.__wawNotifications) return;
      const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wawNotifications;
      if (!handler) return;
      let permission = "__WAW_PERMISSION__";
      const live = new Map();
      const requests = new Map();
      let nextRequest = 1;
      const prefix = Math.random().toString(36).slice(2);
      let nextID = 1;
      const send = (message) => { try { handler.postMessage(message); } catch (e) {} };

      class Notification extends EventTarget {
        constructor(title, options) {
          super();
          if (arguments.length === 0) {
            throw new TypeError("Failed to construct 'Notification': 1 argument required, but only 0 present.");
          }
          const o = options || {};
          let icon = "";
          try { icon = o.icon ? new URL(String(o.icon), location.href).href : ""; } catch (e) {}
          Object.defineProperties(this, {
            title: { value: String(title), enumerable: true },
            body: { value: o.body == null ? "" : String(o.body), enumerable: true },
            tag: { value: o.tag == null ? "" : String(o.tag), enumerable: true },
            icon: { value: icon, enumerable: true },
            data: { value: o.data === undefined ? null : o.data, enumerable: true },
            silent: { value: !!o.silent, enumerable: true },
            requireInteraction: { value: !!o.requireInteraction, enumerable: true },
          });
          this.onclick = null;
          this.onshow = null;
          this.onclose = null;
          this.onerror = null;
          this.__id = prefix + "-" + (nextID++);
          if (permission !== "granted") {
            setTimeout(() => this.__fire("error"), 0);
            return;
          }
          live.set(this.__id, this);
          send({ type: "show", id: this.__id, title: this.title, body: this.body, tag: this.tag, icon: this.icon, silent: this.silent });
          setTimeout(() => this.__fire("show"), 0);
        }
        static get permission() { return permission; }
        static get maxActions() { return 0; }
        static requestPermission(callback) {
          return new Promise((resolve) => {
            const done = (result) => {
              resolve(result);
              if (typeof callback === "function") { try { callback(result); } catch (e) {} }
            };
            if (permission !== "default") { done(permission); return; }
            const id = nextRequest++;
            requests.set(id, done);
            send({ type: "requestPermission", requestID: id });
          });
        }
        close() {
          if (!live.has(this.__id)) return;
          live.delete(this.__id);
          send({ type: "close", id: this.__id });
          this.__fire("close");
        }
        __fire(type) {
          const event = new Event(type, { cancelable: type === "click" });
          const handlerFunction = this["on" + type];
          if (typeof handlerFunction === "function") { try { handlerFunction.call(this, event); } catch (e) { setTimeout(() => { throw e; }); } }
          this.dispatchEvent(event);
        }
      }

      const define = (target, name, value) => {
        try { Object.defineProperty(target, name, { value, writable: true, configurable: true }); }
        catch (e) { try { target[name] = value; } catch (e2) {} }
      };
      define(window, "Notification", Notification);

      // Notifications a page shows through its service worker registration.
      if (window.ServiceWorkerRegistration) {
        const proto = window.ServiceWorkerRegistration.prototype;
        define(proto, "showNotification", function (title, options) {
          if (permission !== "granted") {
            return Promise.reject(new TypeError("No notification permission has been granted for this origin."));
          }
          new Notification(title, options);
          return Promise.resolve();
        });
        define(proto, "getNotifications", function () {
          return Promise.resolve(Array.from(live.values()));
        });
      }

      // navigator.permissions.query({ name: "notifications" })
      if (navigator.permissions && navigator.permissions.query) {
        const query = navigator.permissions.query.bind(navigator.permissions);
        define(navigator.permissions, "query", function (descriptor) {
          if (descriptor && descriptor.name === "notifications") {
            const state = permission === "default" ? "prompt" : permission;
            return Promise.resolve({ name: "notifications", state, onchange: null,
              addEventListener() {}, removeEventListener() {}, dispatchEvent() { return false; } });
          }
          return query(descriptor);
        });
      }

      define(window, "__wawNotifications", {
        setPermission(value) { permission = value; },
        resolvePermission(id, value) {
          permission = value;
          const done = requests.get(id);
          requests.delete(id);
          if (done) done(value);
        },
        click(id) {
          const notification = live.get(id);
          if (!notification) return;
          live.delete(id);
          notification.__fire("click");
          notification.__fire("close");
        },
      });
    })();
    """#
}
