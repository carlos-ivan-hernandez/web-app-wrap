import XCTest
@testable import WebAppWrapKit

final class AppRecordTests: XCTestCase {
    private let settings = AppSettings(name: "Tools/Linear", url: "https://linear.app", icon: "a.svg", zoom: 1.2, iconBackground: "#FFFFFF", iconColor: "#E5E5E5", titleBarColor: "#1A1A1A")

    private func built(version: String?, settings: AppSettings? = nil) -> AppRecord {
        AppRecord(settings: self.settings, lastBuild: BuildStamp(version: version, date: Date(), settings: settings ?? self.settings))
    }

    func testNeverBuilt() {
        XCTAssertEqual(AppRecord(settings: settings).buildReason(currentVersion: "abc", appExists: false), .neverBuilt)
    }

    func testUpToDateIsSkipped() {
        XCTAssertNil(built(version: "abc").buildReason(currentVersion: "abc", appExists: true))
    }

    func testChangedSettings() {
        var old = settings
        old.url = "https://linear.app/team"
        XCTAssertEqual(built(version: "abc", settings: old).buildReason(currentVersion: "abc", appExists: true), .changed)
    }

    func testReplacedIconCountsAsChanged() {
        var old = settings
        old.icon = "old.png"
        XCTAssertEqual(built(version: "abc", settings: old).buildReason(currentVersion: "abc", appExists: true), .changed)
    }

    func testNewVersion() {
        XCTAssertEqual(built(version: "abc").buildReason(currentVersion: "def", appExists: true), .newVersion)
        XCTAssertEqual(built(version: nil).buildReason(currentVersion: "def", appExists: true), .newVersion)
    }

    func testDevelopmentBuildAlwaysRebuilds() {
        XCTAssertEqual(built(version: nil).buildReason(currentVersion: nil, appExists: true), .unknownVersion)
    }

    func testMissingApp() {
        XCTAssertEqual(built(version: "abc").buildReason(currentVersion: "abc", appExists: false), .missing)
    }

    func testBatchEntry() throws {
        let entry = try XCTUnwrap(AppRecord(settings: settings).batchEntry(iconsFolder: URL(fileURLWithPath: "/icons")))
        XCTAssertEqual(entry.location, AppLocation("Tools/Linear"))
        XCTAssertEqual(entry.url.absoluteString, "https://linear.app")
        XCTAssertEqual(entry.image?.path, "/icons/a.svg")
        XCTAssertEqual(entry.zoom, 1.2)
        XCTAssertEqual(entry.iconBackground?.hexString, "#FFFFFF")
        XCTAssertEqual(entry.iconColor?.hexString, "#E5E5E5")
        XCTAssertEqual(entry.titleBarColor?.hexString, "#1A1A1A")
    }

    func testChangedIconBackgroundCountsAsChanged() {
        var old = settings
        old.iconBackground = "#1C1C1C"
        XCTAssertEqual(built(version: "abc", settings: old).buildReason(currentVersion: "abc", appExists: true), .changed)
    }

    /// Lists saved before icon backgrounds existed still load, and their apps aren't marked changed.
    func testSettingsWithoutIconBackgroundStillDecode() throws {
        let json = #"{"name": "A", "url": "https://a.com", "icon": "a.png", "zoom": 1.5}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertNil(decoded.iconBackground)
        XCTAssertNil(decoded.iconColor)
        XCTAssertEqual(decoded, AppSettings(name: "A", url: "https://a.com", icon: "a.png", zoom: 1.5))
    }

    func testLocationKeyIgnoresCase() {
        XCTAssertEqual(AppLocation("Tools/Linear").key, AppLocation("tools/LINEAR").key)
        XCTAssertNotEqual(AppLocation("Tools/Linear").key, AppLocation("Linear").key)
    }
}

final class AppRegistryTests: XCTestCase {
    private var root: URL!
    private var registry: AppRegistry!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AppRegistryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        registry = AppRegistry(folder: root.appendingPathComponent("WebAppWrap"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func file(_ name: String, _ contents: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testEmptyWhenNothingSaved() throws {
        XCTAssertEqual(try registry.load(), [])
    }

    func testUpdateSettingsChangesOnlyThatApp() throws {
        let photos = AppRecord(settings: AppSettings(name: "Photos", url: "https://photos.google.com"))
        let mail = AppRecord(settings: AppSettings(name: "Mail", url: "https://mail.google.com", titleBarColor: "#FFFFFF"))
        try registry.save([photos, mail])

        XCTAssertTrue(try registry.updateSettings(of: photos.id) { $0.titleBarColor = "#336699" })
        XCTAssertEqual(registry.settings(of: photos.id)?.titleBarColor, "#336699")
        XCTAssertEqual(registry.settings(of: mail.id)?.titleBarColor, "#FFFFFF")
        XCTAssertFalse(try registry.updateSettings(of: UUID()) { $0.titleBarColor = "#000000" })
    }

    func testSaveAndLoad() throws {
        let stamp = BuildStamp(version: "abc", date: Date(timeIntervalSince1970: 1_700_000_000), settings: AppSettings(name: "A", url: "https://a.com"))
        let records = [
            AppRecord(settings: AppSettings(name: "A", url: "https://a.com"), lastBuild: stamp),
            AppRecord(settings: AppSettings(name: "B/C", url: "https://c.com", icon: "c.png", zoom: 2, titleBarColor: "#FFFFFF")),
        ]
        try registry.save(records)
        XCTAssertEqual(try registry.load(), records)
    }

    func testImportCopiesIcon() throws {
        let id = UUID()
        let source = try file("photo.PNG", "image-1")
        let name = try registry.importIcon(from: source, for: id, replacing: nil)
        XCTAssertTrue(name.hasPrefix(id.uuidString.lowercased()))
        XCTAssertTrue(name.hasSuffix(".png"))
        XCTAssertEqual(try String(contentsOf: registry.iconURL(name), encoding: .utf8), "image-1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the original stays where it was")
    }

    func testImportingTheSameImageKeepsTheCurrentIcon() throws {
        let id = UUID()
        let current = try registry.importIcon(from: try file("a.png", "same"), for: id, replacing: nil)
        XCTAssertEqual(try registry.importIcon(from: registry.iconURL(current), for: id, replacing: current), current)
        XCTAssertEqual(try registry.importIcon(from: try file("b.png", "same"), for: id, replacing: current), current)
    }

    func testImportingADifferentImageGetsANewName() throws {
        let id = UUID()
        let current = try registry.importIcon(from: try file("a.png", "one"), for: id, replacing: nil)
        let replacement = try registry.importIcon(from: try file("a2.png", "two"), for: id, replacing: current)
        XCTAssertNotEqual(replacement, current)
    }

    func testRetireMovesIconToPreviousIcons() throws {
        let name = try registry.importIcon(from: try file("a.png", "old"), for: UUID(), replacing: nil)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try XCTUnwrap(try registry.retireIcon(name, appName: "Tools/Linear", date: date))
        XCTAssertFalse(FileManager.default.fileExists(atPath: registry.iconURL(name).path))
        XCTAssertEqual(first.deletingLastPathComponent().lastPathComponent, "previous-icons")
        XCTAssertTrue(first.lastPathComponent.hasPrefix("Linear "))
        XCTAssertEqual(first.pathExtension, "png")
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "old")

        // A second icon retired at the same moment doesn't overwrite the first.
        let other = try registry.importIcon(from: try file("b.png", "older"), for: UUID(), replacing: nil)
        let second = try XCTUnwrap(try registry.retireIcon(other, appName: "Linear", date: date))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "old")
    }

    func testRetiringAMissingIconDoesNothing() throws {
        XCTAssertNil(try registry.retireIcon("gone.png", appName: "A"))
    }
}
