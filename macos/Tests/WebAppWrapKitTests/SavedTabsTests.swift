import XCTest
@testable import WebAppWrapKit

final class SavedTabsTests: XCTestCase {
    private let profile = UUID()
    private let a = URL(string: "https://linear.app/a")!
    private let b = URL(string: "https://linear.app/b")!
    private let c = URL(string: "https://linear.app/c")!
    private let other = URL(string: "https://example.com/")!

    private func allowLinear(_ url: URL) -> Bool { url.host == "linear.app" }

    func testKeepsEverythingAllowed() {
        let saved = SavedTabs(windows: [.init(profile: profile, tabs: [a, b, c], selected: 1)])
        XCTAssertEqual(saved.reopenable(isAllowed: allowLinear, profileExists: { _ in true }), saved)
    }

    func testDropsPagesNoLongerAllowedAndFollowsSelection() {
        let saved = SavedTabs(windows: [.init(profile: profile, tabs: [other, a, other, b], selected: 3)])
        let window = saved.reopenable(isAllowed: allowLinear, profileExists: { _ in true }).windows.first
        XCTAssertEqual(window?.tabs, [a, b])
        XCTAssertEqual(window?.selected, 1)
    }

    func testSelectedTabRemovedSelectsTheOneBefore() {
        let saved = SavedTabs(windows: [.init(profile: profile, tabs: [a, b, other, c], selected: 2)])
        XCTAssertEqual(saved.reopenable(isAllowed: allowLinear, profileExists: { _ in true }).windows.first?.selected, 1)
    }

    func testDropsNonWebPagesEmptyWindowsAndDeletedProfiles() {
        let gone = UUID()
        let saved = SavedTabs(windows: [
            .init(profile: profile, tabs: [URL(string: "webkit-extension://x/options.html")!, URL(string: "about:blank")!], selected: 0),
            .init(profile: gone, tabs: [a], selected: 0),
            .init(profile: profile, tabs: [b], selected: 0),
        ])
        let reopenable = saved.reopenable(isAllowed: { _ in true }, profileExists: { $0 != gone })
        XCTAssertEqual(reopenable.windows.map(\.tabs), [[b]])
    }

    func testSavesAndLoads() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("tabs.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        XCTAssertEqual(SavedTabs.load(from: file), SavedTabs())
        let saved = SavedTabs(windows: [.init(profile: profile, tabs: [a, b], selected: 1, frame: CGRect(x: 10, y: 20, width: 800, height: 600))])
        try saved.save(to: file)
        XCTAssertEqual(SavedTabs.load(from: file), saved)
    }
}
