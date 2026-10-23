import Foundation

/// Makes extensions written for Chrome start in WebKit.
///
/// WebKit leaves out some Chrome APIs (history, bookmarks, sessions, search, some events and
/// constants). An extension that touches one of them while starting up throws, and then none
/// of it works: Vimium and Stylish both stop on `chrome.webNavigation.onHistoryStateUpdated`.
/// Installing adds a script that fills them in, run before the extension's own background
/// script and at the top of each of its pages. The added pieces do nothing and return empty
/// results, except history state updates, which are rebuilt from tab URL changes.
///
/// Only the copy in ExtensionStore's folder is changed, never the browser's original.
public enum ExtensionCompat {
    /// Bump when `script` changes, so installed extensions get the new one (see
    /// ExtensionStore.updateCompatibility).
    public static let version = 1

    static let scriptName = "__webappwrap_compat.js"
    static let backgroundName = "__webappwrap_background.js"
    static let markerName = "__webappwrap_compat.json"
    private static let scriptTag = "<script src=\"/\(scriptName)\"></script>"

    /// The version applied to the extension in `folder`, or nil if none was.
    public static func appliedVersion(in folder: URL) -> Int? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(markerName)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["version"] as? Int
    }

    /// Adds the script to the extension in `folder`. Safe to run again on a folder it was
    /// already applied to.
    public static func apply(to folder: URL) throws {
        try Data(script.utf8).write(to: folder.appendingPathComponent(scriptName))
        try addToBackground(in: folder)
        addToPages(in: folder)
        let marker = try JSONSerialization.data(withJSONObject: ["version": version])
        try marker.write(to: folder.appendingPathComponent(markerName))
    }

    /// Runs the script before the background script: a service worker gets a wrapper that loads
    /// both, and a list of background scripts gets it first. A background page is an HTML page,
    /// which addToPages handles.
    private static func addToBackground(in folder: URL) throws {
        let manifestURL = folder.appendingPathComponent("manifest.json")
        guard var manifest = ExtensionManifest.jsonObject(try Data(contentsOf: manifestURL)) as? [String: Any],
              var background = manifest["background"] as? [String: Any]
        else { return }

        if let worker = background["service_worker"] as? String {
            guard worker != backgroundName else { return }
            let path = relativePath(worker)
            let wrapper: String
            if (background["type"] as? String) == "module" {
                wrapper = "import \(jsString("./" + scriptName));\nimport \(jsString("./" + path));\n"
            } else {
                wrapper = "importScripts(\(jsString("/" + scriptName)), \(jsString("/" + path)));\n"
            }
            try Data(wrapper.utf8).write(to: folder.appendingPathComponent(backgroundName))
            background["service_worker"] = backgroundName
        } else if let scripts = background["scripts"] as? [String] {
            guard !scripts.map(relativePath).contains(scriptName) else { return }
            background["scripts"] = [scriptName] + scripts
        } else {
            return
        }
        manifest["background"] = background
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: manifestURL, options: .atomic)
    }

    /// Puts the script at the top of every HTML page in the extension: popups, options pages,
    /// background pages and pages shown in frames (like Vimium's search bar).
    private static func addToPages(in folder: URL) {
        let fileManager = FileManager.default
        guard let files = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let file as URL in files {
            let pathExtension = file.pathExtension.lowercased()
            guard pathExtension == "html" || pathExtension == "htm",
                  let html = try? String(contentsOf: file, encoding: .utf8),
                  !html.contains(scriptTag)
            else { continue }
            try? Data(withScript(html).utf8).write(to: file)
        }
    }

    /// `html` with the script tag right after `<head>`, or after `<html>` if there's no head,
    /// or at the start.
    static func withScript(_ html: String) -> String {
        for element in ["head", "html"] {
            guard let range = html.range(of: "<\(element)(\\s[^>]*)?>", options: [.regularExpression, .caseInsensitive]) else { continue }
            return html.replacingCharacters(in: range, with: html[range] + scriptTag)
        }
        return scriptTag + html
    }

    /// "./js/bg.js" or "/js/bg.js" -> "js/bg.js".
    private static func relativePath(_ path: String) -> String {
        var path = Substring(path)
        while path.hasPrefix("./") { path = path.dropFirst(2) }
        while path.hasPrefix("/") { path = path.dropFirst() }
        return String(path)
    }

    private static func jsString(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text], options: .withoutEscapingSlashes)) ?? Data("[\"\"]".utf8)
        return String(decoding: data, as: UTF8.self).dropFirst().dropLast().description
    }

    // MARK: - The script

    static let script = #"""
    // Added by WebAppWrap: fills in Chrome extension APIs that WebKit doesn't have, so extensions
    // written for Chrome don't stop while starting up. Missing events never fire (except history
    // state updates, rebuilt from tab URL changes), and missing functions do nothing and return
    // empty results.
    (() => {
      const api = globalThis.chrome || globalThis.browser;
      if (!api || !api.runtime || globalThis.__webAppWrapCompatObjects) return;

      function makeEvent() {
        const listeners = new Set();
        return {
          addListener(f) { listeners.add(f); },
          removeListener(f) { listeners.delete(f); },
          hasListener(f) { return listeners.has(f); },
          hasListeners() { return listeners.size > 0; },
          dispatch(...args) { for (const f of listeners) { try { f(...args); } catch (e) { console.error(e); } } },
        };
      }

      // A function that answers with `result` (or result(...args)), by callback or promise.
      function answer(result) {
        return (...args) => {
          const callback = typeof args[args.length - 1] === "function" ? args.pop() : null;
          const value = typeof result === "function" ? result(...args) : result;
          if (callback) { setTimeout(() => callback(value), 0); return; }
          return Promise.resolve(value);
        };
      }
      const nothing = answer(undefined);

      // WebKit can drop a namespace object (chrome.scripting) once nothing refers to it, and
      // make a new one without what's added here, so keep each one that gets something added.
      const patched = new Set([api]);
      try { Object.defineProperty(globalThis, "__webAppWrapCompatObjects", { value: patched }); } catch (e) {}

      function define(target, key, value) {
        try {
          Object.defineProperty(target, key, { value, configurable: true, enumerable: true, writable: true });
          patched.add(target);
        } catch (e) {}
      }

      function addEvents(namespace, names) {
        if (!namespace) return;
        for (const name of names) if (!namespace[name]) define(namespace, name, makeEvent());
      }

      function addNamespace(name, members, events) {
        if (api[name]) return;
        const namespace = Object.assign({}, members);
        addEvents(namespace, events);
        define(api, name, namespace);
      }

      function addConstants(namespace, values) {
        if (!namespace) return;
        for (const [key, value] of Object.entries(values)) if (namespace[key] === undefined) define(namespace, key, value);
      }
      const enumOf = (...names) => Object.fromEntries(names.map((n) => [n.toUpperCase().replace(/-/g, "_"), n]));

      // Events WebKit leaves out of namespaces it has.
      addEvents(api.webNavigation, ["onHistoryStateUpdated", "onReferenceFragmentUpdated", "onCreatedNavigationTarget", "onTabReplaced"]);
      addEvents(api.tabs, ["onReplaced", "onHighlighted", "onAttached", "onDetached", "onZoomChange"]);
      addEvents(api.windows, ["onBoundsChanged"]);
      addEvents(api.runtime, ["onSuspend", "onSuspendCanceled", "onUpdateAvailable", "onRestartRequired"]);

      // Same-page navigations (pushState, #hash changes) show up as URL changes on a tab that
      // has finished loading.
      if (api.webNavigation && api.tabs && api.tabs.onUpdated) {
        const lastURL = new Map();
        api.tabs.onUpdated.addListener((tabId, change, tab) => {
          if (!change.url) return;
          const previous = lastURL.get(tabId);
          lastURL.set(tabId, change.url);
          if (!previous || (tab && tab.status !== "complete")) return;
          const details = { tabId, url: change.url, frameId: 0, parentFrameId: -1, processId: 0, timeStamp: Date.now(), transitionType: "link", transitionQualifiers: [] };
          const page = (url) => url.split("#")[0];
          const event = page(previous) === page(change.url) ? api.webNavigation.onReferenceFragmentUpdated : api.webNavigation.onHistoryStateUpdated;
          if (event && event.dispatch) event.dispatch(details);
        });
        if (api.tabs.onRemoved) api.tabs.onRemoved.addListener((tabId) => lastURL.delete(tabId));
      }

      // Namespaces WebKit doesn't have.
      addNamespace("history", { search: answer([]), getVisits: answer([]), addUrl: nothing, deleteUrl: nothing, deleteRange: nothing, deleteAll: nothing }, ["onVisited", "onVisitRemoved"]);
      addNamespace("bookmarks", {
        get: answer([]), getChildren: answer([]), getRecent: answer([]), getSubTree: answer([]), search: answer([]),
        getTree: answer([{ id: "0", title: "", children: [] }]), create: nothing, move: nothing, update: nothing, remove: nothing, removeTree: nothing,
      }, ["onCreated", "onRemoved", "onChanged", "onMoved", "onChildrenReordered", "onImportBegan", "onImportEnded"]);
      addNamespace("sessions", { getRecentlyClosed: answer([]), getDevices: answer([]), restore: nothing, MAX_SESSION_RESULTS: 25 }, ["onChanged"]);
      addNamespace("search", {
        query: answer((info) => {
          const url = "https://www.google.com/search?q=" + encodeURIComponent((info && info.text) || "");
          const disposition = info && info.disposition;
          if (disposition === "NEW_TAB" || disposition === "NEW_WINDOW") api.tabs.create({ url });
          else if (info && info.tabId) api.tabs.update(info.tabId, { url });
          else api.tabs.update({ url });
        }),
      }, []);
      addNamespace("fontSettings", {
        getFontList: answer([]), getFont: answer({ fontId: "", levelOfControl: "not_controllable" }), setFont: nothing, clearFont: nothing,
        getDefaultFontSize: answer({ pixelSize: 16, levelOfControl: "not_controllable" }),
      }, ["onFontChanged", "onDefaultFontSizeChanged"]);
      addNamespace("idle", { queryState: answer("active"), setDetectionInterval: nothing, getAutoLockDelay: answer(0) }, ["onStateChanged"]);
      addNamespace("tabGroups", { get: nothing, query: answer([]), update: nothing, move: nothing, TAB_GROUP_ID_NONE: -1 }, ["onCreated", "onUpdated", "onMoved", "onRemoved"]);
      addNamespace("notifications", {
        create: answer((id) => (typeof id === "string" ? id : String(Date.now()))), update: answer(false), clear: answer(false),
        getAll: answer({}), getPermissionLevel: answer("granted"),
      }, ["onClicked", "onClosed", "onButtonClicked", "onShowSettings", "onPermissionLevelChanged"]);

      // Constants and enums.
      addConstants(api.scripting, { ExecutionWorld: { ISOLATED: "ISOLATED", MAIN: "MAIN" }, StyleOrigin: { AUTHOR: "AUTHOR", USER: "USER" } });
      addConstants(api.runtime, {
        OnInstalledReason: enumOf("install", "update", "chrome_update", "shared_module_update"),
        OnRestartRequiredReason: enumOf("app_update", "os_update", "periodic"),
        PlatformOs: enumOf("mac", "win", "android", "cros", "linux", "openbsd", "fuchsia"),
        ContextType: enumOf("TAB", "POPUP", "BACKGROUND", "OFFSCREEN_DOCUMENT", "SIDE_PANEL"),
      });
      addConstants(api.tabs, {
        TAB_ID_NONE: -1, TAB_INDEX_NONE: -1, TabStatus: enumOf("unloaded", "loading", "complete"),
        WindowType: enumOf("normal", "popup", "panel", "app", "devtools"),
        ZoomSettingsMode: enumOf("automatic", "manual", "disabled"), ZoomSettingsScope: enumOf("per-origin", "per-tab"),
      });
      addConstants(api.windows, {
        WINDOW_ID_NONE: -1, WINDOW_ID_CURRENT: -2, WindowType: enumOf("normal", "popup", "panel", "app", "devtools"),
        WindowState: enumOf("normal", "minimized", "maximized", "fullscreen", "locked-fullscreen"), CreateType: enumOf("normal", "popup", "panel"),
      });

      // Context menus: Chrome still takes Manifest V2's names for the toolbar button.
      const contextTypes = enumOf("all", "page", "frame", "selection", "link", "editable", "image", "video", "audio", "launcher", "browser_action", "page_action", "action");
      for (const menus of new Set([api.contextMenus, api.menus])) {
        if (!menus) continue;
        addConstants(menus, { ContextType: contextTypes, ItemType: enumOf("normal", "checkbox", "radio", "separator"), ACTION_MENU_TOP_LEVEL_LIMIT: 6 });
        const fix = (props) => {
          if (!props || !Array.isArray(props.contexts)) return props;
          const contexts = props.contexts.map((c) => (c === "browser_action" || c === "page_action" ? "action" : c));
          return Object.assign({}, props, { contexts: [...new Set(contexts)] });
        };
        const create = menus.create, update = menus.update;
        if (typeof create === "function") define(menus, "create", function (props, callback) { return create.call(this, fix(props), callback); });
        if (typeof update === "function") define(menus, "update", function (id, props, callback) { return update.call(this, id, fix(props), callback); });
      }
    })();
    """#
}
