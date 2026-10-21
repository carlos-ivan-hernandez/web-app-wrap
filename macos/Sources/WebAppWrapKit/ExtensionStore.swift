import Foundation

/// A browser extension installed once in WebAppWrap and shared by the apps it creates.
public struct InstalledExtension: Codable, Equatable, Identifiable {
    /// A slug of the extension's name, e.g. "dark-reader". Reinstalling an extension with the
    /// same name updates it. Also the extension's identity inside each app, so its storage
    /// survives updates.
    public var id: String
    public var name: String
    public var version: String
    /// The unpacked extension, relative to ExtensionStore's extensions folder.
    public var folder: String
    /// On for apps that have no setting of their own.
    public var enabledByDefault: Bool
    /// App ID (AppRecord.id) -> on or off, for apps that differ from the default.
    public var apps: [String: Bool]
    /// Where it came from, e.g. "Google Chrome" or a file name.
    public var source: String?
    public var installed: Date

    public init(
        id: String, name: String, version: String, folder: String,
        enabledByDefault: Bool = true, apps: [String: Bool] = [:], source: String? = nil, installed: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.folder = folder
        self.enabledByDefault = enabledByDefault
        self.apps = apps
        self.source = source
        self.installed = installed
    }

    /// Apps without an ID (made from the command line) get the default.
    public func isEnabled(forApp appID: UUID?) -> Bool {
        guard let appID else { return enabledByDefault }
        return apps[appID.uuidString.lowercased()] ?? enabledByDefault
    }

    /// Turns the extension on or off for one app. Matching the default removes the app's own setting.
    public mutating func setEnabled(_ enabled: Bool, forApp appID: UUID) {
        let key = appID.uuidString.lowercased()
        apps[key] = enabled == enabledByDefault ? nil : enabled
    }

    /// Changes the default for apps without their own setting. Apps whose setting now matches
    /// the default go back to following it.
    public mutating func setEnabledByDefault(_ enabled: Bool) {
        enabledByDefault = enabled
        apps = apps.filter { $0.value != enabled }
    }
}

/// extensions.json and the unpacked extensions, next to the app list in
/// ~/Library/Application Support/WebAppWrap:
///
///     extensions.json                  installed extensions and which apps use them
///     extensions/<id>/<version-tag>/   each extension's files
///
/// WebAppWrap installs and configures extensions. Every app it created reads this list when it
/// opens or comes to the front, and loads the extensions that are on for it.
public struct ExtensionStore {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public static var standard: ExtensionStore { ExtensionStore(folder: AppRegistry.standard.folder) }

    public var listFile: URL { folder.appendingPathComponent("extensions.json") }
    public var extensionsFolder: URL { folder.appendingPathComponent("extensions", isDirectory: true) }

    public func resourceURL(for installed: InstalledExtension) -> URL {
        extensionsFolder.appendingPathComponent(installed.folder, isDirectory: true)
    }

    // MARK: - The list

    private struct ListFile: Codable {
        var extensions: [InstalledExtension]
    }

    public func load() throws -> [InstalledExtension] {
        guard FileManager.default.fileExists(atPath: listFile.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ListFile.self, from: Data(contentsOf: listFile)).extensions
    }

    public func save(_ extensions: [InstalledExtension]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(ListFile(extensions: extensions)).write(to: listFile, options: .atomic)
    }

    /// Re-reads the list, applies `change` to the extension `id`, and saves. Re-reading first
    /// keeps changes made meanwhile by WebAppWrap or another app.
    @discardableResult
    public func update(_ id: String, _ change: (inout InstalledExtension) -> Void) throws -> [InstalledExtension] {
        var list = try load()
        guard let index = list.firstIndex(where: { $0.id == id }) else { return list }
        change(&list[index])
        try save(list)
        return list
    }

    // MARK: - Installing

    /// Copies the unpacked extension at `source` into the extensions folder and adds it to the
    /// list, or updates the one with the same name (keeping its app settings). Saves the list.
    @discardableResult
    public func install(from source: URL, manifest: ExtensionManifest, sourceName: String?) throws -> InstalledExtension {
        let fileManager = FileManager.default
        var list = try load()
        let id = InputNormalizer.slug(manifest.name)
        let existing = list.first { $0.id == id }

        // A new folder for every install, so an app still using the old files isn't disturbed.
        let tag = "\(InputNormalizer.fileSafeName(manifest.version))-\(UUID().uuidString.prefix(8).lowercased())"
        let relative = "\(id)/\(tag)"
        let destination = extensionsFolder.appendingPathComponent(relative, isDirectory: true)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)

        var installed = existing ?? InstalledExtension(id: id, name: manifest.name, version: manifest.version, folder: relative)
        installed.name = manifest.name
        installed.version = manifest.version
        installed.folder = relative
        installed.source = sourceName
        installed.installed = Date()
        if let index = list.firstIndex(where: { $0.id == id }) {
            list[index] = installed
        } else {
            list.append(installed)
        }
        try save(list)

        // Keep the new version and the one it replaced; older ones are no longer in use.
        let keep = Set([relative, existing?.folder].compactMap { $0 })
        let versions = (try? fileManager.contentsOfDirectory(at: destination.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
        for version in versions where !keep.contains("\(id)/\(version.lastPathComponent)") {
            try? fileManager.removeItem(at: version)
        }
        return installed
    }

    /// Takes the extension off the list and deletes its files. Apps drop it the next time they
    /// come to the front.
    public func uninstall(_ id: String) throws {
        var list = try load()
        list.removeAll { $0.id == id }
        try save(list)
        try? FileManager.default.removeItem(at: extensionsFolder.appendingPathComponent(id, isDirectory: true))
    }
}

/// Extensions installed in Chrome and other Chromium browsers, which keep them unpacked on disk.
public struct BrowserExtension: Equatable, Identifiable {
    public let browser: String
    public let profile: String
    /// The browser's own ID for the extension (32 letters).
    public let browserID: String
    public let folder: URL
    public let manifest: ExtensionManifest

    public var id: String { "\(browser)/\(browserID)" }

    /// Where each browser keeps its profiles, under ~/Library/Application Support.
    public static let browsers: [(name: String, path: String)] = [
        ("Google Chrome", "Google/Chrome"),
        ("Google Chrome Beta", "Google/Chrome Beta"),
        ("Google Chrome Dev", "Google/Chrome Dev"),
        ("Google Chrome Canary", "Google/Chrome Canary"),
        ("Chromium", "Chromium"),
        ("Brave", "BraveSoftware/Brave-Browser"),
        ("Brave Beta", "BraveSoftware/Brave-Browser-Beta"),
        ("Brave Nightly", "BraveSoftware/Brave-Browser-Nightly"),
        ("Microsoft Edge", "Microsoft Edge"),
        ("Microsoft Edge Beta", "Microsoft Edge Beta"),
        ("Microsoft Edge Dev", "Microsoft Edge Dev"),
        ("Microsoft Edge Canary", "Microsoft Edge Canary"),
        ("Helium", "net.imput.helium"),
        ("Vivaldi", "Vivaldi"),
        ("Vivaldi Snapshot", "Vivaldi Snapshot"),
        ("Arc", "Arc/User Data"),
        ("Dia", "Dia/User Data"),
        ("Comet", "Comet"),
        ("Opera", "com.operasoftware.Opera"),
        ("Opera GX", "com.operasoftware.OperaGX"),
        ("Yandex", "Yandex/YandexBrowser"),
        ("Thorium", "Thorium"),
    ]

    /// Every extension (not theme) in every profile of every browser, newest version of each,
    /// listed once per browser.
    public static func find(applicationSupport: URL) -> [BrowserExtension] {
        let fileManager = FileManager.default
        func folders(_ url: URL) -> [URL] {
            ((try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        var found: [BrowserExtension] = []
        for browser in browsers {
            var seen = Set<String>()
            // Most browsers keep each profile in a subfolder ("Default", "Profile 1"); Opera keeps
            // its main profile in the browser folder itself.
            let browserFolder = applicationSupport.appendingPathComponent(browser.path, isDirectory: true)
            for profile in [browserFolder] + folders(browserFolder) {
                for extensionFolder in folders(profile.appendingPathComponent("Extensions", isDirectory: true)) {
                    let browserID = extensionFolder.lastPathComponent
                    guard !seen.contains(browserID) else { continue }
                    let newestFirst = folders(extensionFolder).sorted {
                        $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
                    }
                    for version in newestFirst {
                        guard let manifest = try? ExtensionManifest.read(from: version) else { continue }
                        if !manifest.isTheme {
                            found.append(BrowserExtension(
                                browser: browser.name, profile: profile == browserFolder ? "Default" : profile.lastPathComponent,
                                browserID: browserID, folder: version, manifest: manifest
                            ))
                            seen.insert(browserID)
                        }
                        break
                    }
                }
            }
        }
        return found.sorted {
            ($0.manifest.name.lowercased(), $0.browser) < ($1.manifest.name.lowercased(), $1.browser)
        }
    }
}
