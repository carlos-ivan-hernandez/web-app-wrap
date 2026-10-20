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

        let found = BrowserExtension.find(applicationSupport: support)
        XCTAssertEqual(found.map(\.manifest.name), ["Brave One", "Vimium"])
        XCTAssertEqual(found[1].manifest.version, "2.10.0", "newest version wins")
        XCTAssertEqual(found[1].browser, "Google Chrome")
        XCTAssertEqual(found[1].browserID, vimium)
    }
}
