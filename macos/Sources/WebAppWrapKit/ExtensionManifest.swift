import Foundation

/// The parts of a browser extension's manifest.json that WebAppWrap shows and stores.
/// Chrome, Edge, Brave and Safari web extensions all use this format.
public struct ExtensionManifest: Equatable {
    public var name: String
    public var version: String
    public var description: String?
    public var manifestVersion: Int
    /// API permissions such as "storage" or "tabs" (host patterns are in `hostPermissions`).
    public var permissions: [String]
    /// Sites the extension can read and change: host permissions plus content script matches.
    public var hostPermissions: [String]
    public var isTheme: Bool
    /// The largest icon, relative to the extension's folder.
    public var iconPath: String?

    public struct ReadError: LocalizedError, Equatable {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Reads `folder`/manifest.json, filling in localized strings ("__MSG_appName__").
    public static func read(from folder: URL) throws -> ExtensionManifest {
        let file = folder.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: file) else {
            throw ReadError(message: "\(folder.lastPathComponent) has no manifest.json, so it isn’t an unpacked extension.")
        }
        return try parse(data) { locale in
            try? Data(contentsOf: folder.appendingPathComponent("_locales/\(locale)/messages.json"))
        }
    }

    /// `messages` returns a locale's messages.json, if the extension has one.
    public static func parse(_ data: Data, messages: (String) -> Data? = { _ in nil }) throws -> ExtensionManifest {
        guard let manifest = jsonObject(data) as? [String: Any] else {
            throw ReadError(message: "manifest.json isn’t valid JSON.")
        }
        guard let manifestVersion = manifest["manifest_version"] as? Int, manifestVersion == 2 || manifestVersion == 3 else {
            throw ReadError(message: "manifest.json needs a manifest_version of 2 or 3.")
        }

        let table = messageTable(defaultLocale: manifest["default_locale"] as? String, messages: messages)
        func localized(_ value: Any?) -> String? {
            guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            guard text.hasPrefix("__MSG_"), text.hasSuffix("__"), text.count > 8 else { return text }
            let key = String(text.dropFirst(6).dropLast(2)).lowercased()
            return table[key] ?? text
        }

        guard let name = localized(manifest["name"]) else { throw ReadError(message: "manifest.json has no name.") }
        guard let version = manifest["version"] as? String, !version.isEmpty else {
            throw ReadError(message: "manifest.json has no version.")
        }

        var permissions: [String] = []
        var hosts: [String] = []
        for permission in (manifest["permissions"] as? [Any] ?? []).compactMap({ $0 as? String }) {
            if isHostPattern(permission) { hosts.append(permission) } else { permissions.append(permission) }
        }
        hosts += (manifest["host_permissions"] as? [Any] ?? []).compactMap { $0 as? String }
        for script in manifest["content_scripts"] as? [[String: Any]] ?? [] {
            hosts += (script["matches"] as? [Any] ?? []).compactMap { $0 as? String }
        }

        let icons = (manifest["icons"] as? [String: Any] ?? [:])
            .compactMap { key, value in Int(key).flatMap { size in (value as? String).map { (size, $0) } } }
            .max { $0.0 < $1.0 }

        return ExtensionManifest(
            name: name,
            version: version,
            description: localized(manifest["description"]),
            manifestVersion: manifestVersion,
            permissions: unique(permissions),
            hostPermissions: unique(hosts),
            isTheme: manifest["theme"] != nil,
            iconPath: icons?.1
        )
    }

    // MARK: - What the extension can do

    public enum SiteAccess: Equatable {
        case none
        case allSites
        case sites([String])
    }

    public var siteAccess: SiteAccess {
        if hostPermissions.isEmpty { return .none }
        let everything: Set<String> = ["<all_urls>", "*://*/*", "http://*/*", "https://*/*"]
        if hostPermissions.contains(where: everything.contains) { return .allSites }
        return .sites(hostPermissions)
    }

    /// Plain-language lines for the install confirmation.
    public var accessSummary: [String] {
        var lines: [String] = []
        switch siteAccess {
        case .none: break
        case .allSites: lines.append("Read and change every website")
        case let .sites(patterns):
            let shown = patterns.prefix(4).joined(separator: ", ")
            lines.append("Read and change \(shown)\(patterns.count > 4 ? " and \(patterns.count - 4) more" : "")")
        }
        let described: [(String, String)] = [
            ("tabs", "See the address and title of every tab"),
            ("history", "Read your browsing history"),
            ("cookies", "Read and change cookies"),
            ("declarativeNetRequest", "Block or change network requests"),
            ("declarativeNetRequestWithHostAccess", "Block or change network requests"),
            ("webRequest", "Watch network requests"),
            ("clipboardRead", "Read the clipboard"),
            ("clipboardWrite", "Write to the clipboard"),
            ("downloads", "Manage downloads"),
        ]
        for (permission, line) in described where permissions.contains(permission) && !lines.contains(line) {
            lines.append(line)
        }
        return lines
    }

    /// Permissions WebKit doesn't support, which usually mean the extension won't fully work.
    public var unsupportedPermissions: [String] {
        let unsupported: [String: String] = [
            "nativeMessaging": "talks to a desktop app (nativeMessaging)",
            "webRequestBlocking": "blocks requests with webRequestBlocking, which WebKit doesn’t have",
            "identity": "signs in through the browser (identity)",
            "debugger": "uses the debugger API",
            "tabCapture": "captures tabs (tabCapture)",
            "desktopCapture": "captures the screen (desktopCapture)",
            "sidePanel": "uses a side panel",
        ]
        return permissions.compactMap { unsupported[$0] }
    }

    // MARK: - Helpers

    private static func isHostPattern(_ permission: String) -> Bool {
        permission == "<all_urls>" || permission.contains("://")
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    /// Lowercased message name -> text, from the default locale, falling back to English.
    private static func messageTable(defaultLocale: String?, messages: (String) -> Data?) -> [String: String] {
        let locales = [defaultLocale, "en", "en_US"].compactMap { $0 }
        for locale in locales {
            guard let data = messages(locale), let object = jsonObject(data) as? [String: Any] else { continue }
            var table: [String: String] = [:]
            for (key, value) in object {
                if let message = (value as? [String: Any])?["message"] as? String {
                    table[key.lowercased()] = message
                }
            }
            return table
        }
        return [:]
    }

    /// Manifests are JSON, but Chrome tolerates comments in them, so allow those where Foundation can.
    private static func jsonObject(_ data: Data) -> Any? {
        var data = data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        if let object = try? JSONSerialization.jsonObject(with: data) { return object }
        #if canImport(Darwin)
        return try? JSONSerialization.jsonObject(with: data, options: .json5Allowed)
        #else
        return nil
        #endif
    }

    /// The folder holding manifest.json: `folder` itself, or its only subfolder (as in many zips).
    public static func root(in folder: URL) -> URL? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: folder.appendingPathComponent("manifest.json").path) { return folder }
        let children = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" } ?? []
        guard children.count == 1, let only = children.first,
              fileManager.fileExists(atPath: only.appendingPathComponent("manifest.json").path)
        else { return nil }
        return only
    }
}

/// Chrome's .crx packages are a zip file behind a signed header.
public enum CRXFile {
    public struct FormatError: LocalizedError {
        public var errorDescription: String? { "That file isn’t a .crx extension package." }
    }

    /// The zip inside a .crx file. A plain zip is returned unchanged.
    public static func zipData(from data: Data) throws -> Data {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return data }
        guard bytes.count >= 12, bytes.starts(with: Array("Cr24".utf8)) else { throw FormatError() }
        func uint32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        let start: Int
        switch uint32(4) {
        case 2:
            // Public key length and signature length follow the version.
            guard bytes.count >= 16 else { throw FormatError() }
            start = 16 + uint32(8) + uint32(12)
        case 3:
            start = 12 + uint32(8)
        default:
            throw FormatError()
        }
        guard start < bytes.count, bytes[start...].starts(with: [0x50, 0x4B, 0x03, 0x04]) else { throw FormatError() }
        return Data(bytes[start...])
    }
}
