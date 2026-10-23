import XCTest
@testable import WebAppWrapKit

final class ExtensionManifestTests: XCTestCase {
    func testManifestV3() throws {
        let manifest = try ExtensionManifest.parse(Data(#"""
        {
          "manifest_version": 3,
          "name": "Dark Reader",
          "version": "4.9.99",
          "permissions": ["storage", "tabs", "scripting"],
          "host_permissions": ["<all_urls>"],
          "icons": {"16": "icons/16.png", "128": "icons/128.png", "48": "icons/48.png"}
        }
        """#.utf8))
        XCTAssertEqual(manifest.name, "Dark Reader")
        XCTAssertEqual(manifest.version, "4.9.99")
        XCTAssertEqual(manifest.manifestVersion, 3)
        XCTAssertEqual(manifest.permissions, ["storage", "tabs", "scripting"])
        XCTAssertEqual(manifest.siteAccess, .allSites)
        XCTAssertEqual(manifest.iconPath, "icons/128.png")
        XCTAssertEqual(manifest.accessSummary, ["Read and change every website", "See the address and title of every tab"])
        XCTAssertEqual(manifest.unsupportedPermissions, [])
    }

    func testManifestV2HostsInPermissionsAndContentScripts() throws {
        let manifest = try ExtensionManifest.parse(Data(#"""
        {
          "manifest_version": 2, "name": "Old", "version": "1",
          "permissions": ["https://example.com/*", "webRequest", "webRequestBlocking"],
          "content_scripts": [{"matches": ["https://docs.example.com/*", "https://example.com/*"], "js": ["a.js"]}]
        }
        """#.utf8))
        XCTAssertEqual(manifest.permissions, ["webRequest", "webRequestBlocking"])
        XCTAssertEqual(manifest.hostPermissions, ["https://example.com/*", "https://docs.example.com/*"])
        XCTAssertEqual(manifest.siteAccess, .sites(["https://example.com/*", "https://docs.example.com/*"]))
        XCTAssertEqual(manifest.unsupportedPermissions.count, 1)
    }

    func testLocalizedName() throws {
        let manifest = try ExtensionManifest.parse(Data(#"""
        {"manifest_version": 3, "name": "__MSG_extName__", "description": "__MSG_missing__",
         "version": "2.1", "default_locale": "de"}
        """#.utf8)) { locale in
            locale == "de" ? Data(#"{"EXTNAME": {"message": "Vimium"}}"#.utf8) : nil
        }
        XCTAssertEqual(manifest.name, "Vimium")
        XCTAssertEqual(manifest.description, "__MSG_missing__")
    }

    func testTheme() throws {
        let manifest = try ExtensionManifest.parse(Data(#"{"manifest_version": 3, "name": "T", "version": "1", "theme": {}}"#.utf8))
        XCTAssertTrue(manifest.isTheme)
        XCTAssertEqual(manifest.siteAccess, .none)
    }

    func testRejectsBadManifests() {
        XCTAssertThrowsError(try ExtensionManifest.parse(Data("not json".utf8)))
        XCTAssertThrowsError(try ExtensionManifest.parse(Data(#"{"manifest_version": 1, "name": "A", "version": "1"}"#.utf8)))
        XCTAssertThrowsError(try ExtensionManifest.parse(Data(#"{"manifest_version": 3, "version": "1"}"#.utf8)))
        XCTAssertThrowsError(try ExtensionManifest.parse(Data(#"{"manifest_version": 3, "name": "A"}"#.utf8)))
    }
}

final class CRXFileTests: XCTestCase {
    private let zip = Data([0x50, 0x4B, 0x03, 0x04, 1, 2, 3])

    private func le(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    func testPlainZipPassesThrough() throws {
        XCTAssertEqual(try CRXFile.zipData(from: zip), zip)
    }

    func testVersion3() throws {
        var crx = Data("Cr24".utf8) + le(3) + le(5) + Data([9, 9, 9, 9, 9])
        crx += zip
        XCTAssertEqual(try CRXFile.zipData(from: crx), zip)
    }

    func testVersion2() throws {
        var crx = Data("Cr24".utf8) + le(2) + le(3) + le(2) + Data([7, 7, 7, 8, 8])
        crx += zip
        XCTAssertEqual(try CRXFile.zipData(from: crx), zip)
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try CRXFile.zipData(from: Data("hello world!".utf8)))
        XCTAssertThrowsError(try CRXFile.zipData(from: Data("Cr24".utf8) + le(3) + le(500)))
    }
}

final class ExtensionStoreTests: XCTestCase {
    private var root: URL!
    private var store: ExtensionStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ExtensionStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = ExtensionStore(folder: root.appendingPathComponent("WebAppWrap"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// An unpacked extension folder with a manifest.
    private func unpacked(name: String, version: String) throws -> (URL, ExtensionManifest) {
        let folder = root.appendingPathComponent("src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = #"{"manifest_version": 3, "name": "\#(name)", "version": "\#(version)"}"#
        try Data(json.utf8).write(to: folder.appendingPathComponent("manifest.json"))
        return (folder, try ExtensionManifest.read(from: folder))
    }

    func testInstallCopiesAndLists() throws {
        let (source, manifest) = try unpacked(name: "Dark Reader", version: "4.9.99")
        let installed = try store.install(from: source, manifest: manifest, sourceName: "Google Chrome")
        XCTAssertEqual(installed.id, "dark-reader")
        XCTAssertTrue(installed.enabledByDefault)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.resourceURL(for: installed).appendingPathComponent("manifest.json").path))
        XCTAssertEqual(try store.load().map(\.id), ["dark-reader"])
    }

    func testUpdateKeepsAppSettingsAndPrunesOldVersions() throws {
        let app = UUID()
        let (v1, m1) = try unpacked(name: "Vimium", version: "1")
        let first = try store.install(from: v1, manifest: m1, sourceName: nil)
        try store.update("vimium") { $0.setEnabled(false, forApp: app) }

        let (v2, m2) = try unpacked(name: "Vimium", version: "2")
        let second = try store.install(from: v2, manifest: m2, sourceName: nil)
        let (v3, m3) = try unpacked(name: "Vimium", version: "3")
        let third = try store.install(from: v3, manifest: m3, sourceName: nil)

        let list = try store.load()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].version, "3")
        XCTAssertFalse(list[0].isEnabled(forApp: app))
        let fileManager = FileManager.default
        XCTAssertFalse(fileManager.fileExists(atPath: store.resourceURL(for: first).path), "two versions back is removed")
        XCTAssertTrue(fileManager.fileExists(atPath: store.resourceURL(for: second).path), "the replaced version is kept")
        XCTAssertTrue(fileManager.fileExists(atPath: store.resourceURL(for: third).path))
    }

    func testInstallAddsCompatibilityScript() throws {
        let (source, manifest) = try unpacked(name: "Vimium", version: "2")
        let installed = try store.install(from: source, manifest: manifest, sourceName: nil)
        let folder = store.resourceURL(for: installed)
        XCTAssertEqual(ExtensionCompat.appliedVersion(in: folder), ExtensionCompat.version)
        XCTAssertNil(ExtensionCompat.appliedVersion(in: source), "the original isn't changed")
        XCTAssertEqual(store.updateCompatibility(), [], "nothing to update")
    }

    func testUpdateCompatibilityCopiesOldInstalls() throws {
        // As an older WebAppWrap left it: copied, without the script.
        let (source, _) = try unpacked(name: "Stylish", version: "3")
        let old = InstalledExtension(id: "stylish", name: "Stylish", version: "3", folder: "stylish/3-old", apps: [UUID().uuidString.lowercased(): false])
        try FileManager.default.createDirectory(at: store.extensionsFolder.appendingPathComponent("stylish"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: store.resourceURL(for: old))
        try store.save([old])

        XCTAssertEqual(store.updateCompatibility(), ["stylish"])
        let updated = try XCTUnwrap(store.load().first)
        XCTAssertNotEqual(updated.folder, old.folder)
        XCTAssertEqual(updated.apps, old.apps, "app settings are kept")
        XCTAssertEqual(ExtensionCompat.appliedVersion(in: store.resourceURL(for: updated)), ExtensionCompat.version)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.resourceURL(for: old).path), "an app may still be using the old copy")
        XCTAssertEqual(store.updateCompatibility(), [])
    }

    func testUninstall() throws {
        let (source, manifest) = try unpacked(name: "Gone", version: "1")
        let installed = try store.install(from: source, manifest: manifest, sourceName: nil)
        try store.uninstall("gone")
        XCTAssertEqual(try store.load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.resourceURL(for: installed).path))
    }

    func testPerAppSettings() {
        let on = UUID(), off = UUID(), plain = UUID()
        var installed = InstalledExtension(id: "x", name: "X", version: "1", folder: "x/1")
        installed.setEnabled(false, forApp: off)
        installed.setEnabled(true, forApp: on)
        XCTAssertEqual(installed.apps, [off.uuidString.lowercased(): false], "matching the default stores nothing")
        XCTAssertTrue(installed.isEnabled(forApp: plain))
        XCTAssertFalse(installed.isEnabled(forApp: off))
        XCTAssertTrue(installed.isEnabled(forApp: nil))

        installed.setEnabledByDefault(false)
        XCTAssertFalse(installed.isEnabled(forApp: plain), "apps without a setting follow the new default")
        XCTAssertFalse(installed.isEnabled(forApp: off))
        XCTAssertEqual(installed.apps, [:], "an app turned off now matches the default")
        XCTAssertFalse(installed.isEnabled(forApp: nil))

        installed.setEnabled(true, forApp: on)
        installed.setEnabledByDefault(true)
        XCTAssertTrue(installed.isEnabled(forApp: on))
        XCTAssertEqual(installed.apps, [:])
    }

    func testFindsBrowserExtensions() throws {
        let support = root.appendingPathComponent("Application Support")
        func add(_ path: String, _ json: String) throws {
            let folder = support.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(json.utf8).write(to: folder.appendingPathComponent("manifest.json"))
        }
        let vimium = "dbepggeogbaibhgnhhndojpepiihcmeb"
        try add("Google/Chrome/Default/Extensions/\(vimium)/2.1.0_0", #"{"manifest_version": 3, "name": "Vimium", "version": "2.1.0"}"#)
        try add("Google/Chrome/Default/Extensions/\(vimium)/2.10.0_0", #"{"manifest_version": 3, "name": "Vimium", "version": "2.10.0"}"#)
        try add("Google/Chrome/Profile 1/Extensions/\(vimium)/2.10.0_0", #"{"manifest_version": 3, "name": "Vimium", "version": "2.10.0"}"#)
        try add("Google/Chrome/Default/Extensions/themeid/1_0", #"{"manifest_version": 3, "name": "Theme", "version": "1", "theme": {}}"#)
        try add("BraveSoftware/Brave-Browser/Default/Extensions/abc/1_0", #"{"manifest_version": 3, "name": "Brave One", "version": "1"}"#)
        try add("net.imput.helium/Default/Extensions/def/1_0", #"{"manifest_version": 3, "name": "Helium One", "version": "1"}"#)
        try add("com.operasoftware.Opera/Extensions/ghi/1_0", #"{"manifest_version": 3, "name": "Opera One", "version": "1"}"#)

        let found = BrowserExtension.find(applicationSupport: support)
        XCTAssertEqual(found.map(\.manifest.name), ["Brave One", "Helium One", "Opera One", "Vimium"])
        XCTAssertEqual(found[1].browser, "Helium")
        XCTAssertEqual(found[2].browser, "Opera")
        XCTAssertEqual(found[2].profile, "Default", "Opera's main profile is the browser folder itself")
        XCTAssertEqual(found[3].manifest.version, "2.10.0", "newest version wins")
        XCTAssertEqual(found[3].browser, "Google Chrome")
        XCTAssertEqual(found[3].browserID, vimium)
    }
}

final class ExtensionCompatTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ExtensionCompatTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("ui"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ text: String, to path: String) throws {
        try Data(text.utf8).write(to: folder.appendingPathComponent(path))
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)
    }

    private func background() throws -> [String: Any] {
        let data = try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(manifest["background"] as? [String: Any])
    }

    func testServiceWorkerGetsWrapper() throws {
        try write(#"{"manifest_version": 3, "name": "A", "version": "1", "background": {"service_worker": "./js/bg.js"}}"#, to: "manifest.json")
        try ExtensionCompat.apply(to: folder)
        XCTAssertEqual(try background()["service_worker"] as? String, "__webappwrap_background.js")
        XCTAssertEqual(try read("__webappwrap_background.js"), #"importScripts("/__webappwrap_compat.js", "/js/bg.js");"# + "\n")
        XCTAssertTrue(try read("__webappwrap_compat.js").contains("onHistoryStateUpdated"))

        try ExtensionCompat.apply(to: folder)
        XCTAssertEqual(try read("__webappwrap_background.js"), #"importScripts("/__webappwrap_compat.js", "/js/bg.js");"# + "\n", "applying again changes nothing")
    }

    func testModuleServiceWorker() throws {
        try write(#"{"manifest_version": 3, "name": "A", "version": "1", "background": {"service_worker": "bg.js", "type": "module"}}"#, to: "manifest.json")
        try ExtensionCompat.apply(to: folder)
        XCTAssertEqual(try background()["type"] as? String, "module")
        XCTAssertEqual(try read("__webappwrap_background.js"), "import \"./__webappwrap_compat.js\";\nimport \"./bg.js\";\n")
    }

    func testBackgroundScriptsGetItFirst() throws {
        try write(#"{"manifest_version": 2, "name": "A", "version": "1", "background": {"scripts": ["a.js", "b.js"]}}"#, to: "manifest.json")
        try ExtensionCompat.apply(to: folder)
        try ExtensionCompat.apply(to: folder)
        XCTAssertEqual(try background()["scripts"] as? [String], ["__webappwrap_compat.js", "a.js", "b.js"])
    }

    func testPages() throws {
        try write(#"{"manifest_version": 3, "name": "A", "version": "1"}"#, to: "manifest.json")
        try write("<!doctype html><html><HEAD lang=en><title>P</title></HEAD></html>", to: "ui/popup.html")
        try ExtensionCompat.apply(to: folder)
        try ExtensionCompat.apply(to: folder)
        XCTAssertEqual(try read("ui/popup.html"), #"<!doctype html><html><HEAD lang=en><script src="/__webappwrap_compat.js"></script><title>P</title></HEAD></html>"#)
        XCTAssertEqual(ExtensionCompat.withScript("<html><header>x</header></html>"), #"<html><script src="/__webappwrap_compat.js"></script><header>x</header></html>"#)
        XCTAssertEqual(ExtensionCompat.withScript("<p>x</p>"), #"<script src="/__webappwrap_compat.js"></script><p>x</p>"#)
    }

    func testOptionalPermissions() throws {
        let manifest = try ExtensionManifest.parse(Data(#"{"manifest_version": 3, "name": "B", "version": "1", "optional_permissions": ["nativeMessaging", "https://*/*"]}"#.utf8))
        XCTAssertEqual(manifest.optionalPermissions, ["nativeMessaging"])
    }
}
