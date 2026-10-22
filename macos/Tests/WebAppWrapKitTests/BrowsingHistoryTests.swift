import XCTest
@testable import WebAppWrapKit

final class BrowsingHistoryTests: XCTestCase {
    private let a = URL(string: "https://linear.app/team/a")!
    private let b = URL(string: "https://linear.app/team/b")!

    func testNewestFirst() {
        var history = BrowsingHistory()
        history.recordVisit(url: a, title: "A")
        history.recordVisit(url: b, title: "B")
        XCTAssertEqual(history.entries.map(\.url), [b, a])
    }

    func testRevisitingNewestPageUpdatesIt() {
        var history = BrowsingHistory()
        let later = Date(timeIntervalSinceNow: 60)
        history.recordVisit(url: a, title: "")
        history.recordVisit(url: a, title: "A", date: later)
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries[0].title, "A")
        XCTAssertEqual(history.entries[0].date, later)
    }

    func testRevisitingOlderPageAddsAVisit() {
        var history = BrowsingHistory()
        history.recordVisit(url: a, title: "A")
        history.recordVisit(url: b, title: "B")
        history.recordVisit(url: a, title: "A")
        XCTAssertEqual(history.entries.map(\.url), [a, b, a])
        XCTAssertEqual(history.recent(limit: 10).map(\.url), [a, b])
    }

    func testSkipsNonWebPages() {
        var history = BrowsingHistory()
        history.recordVisit(url: URL(string: "about:blank")!, title: nil)
        history.recordVisit(url: URL(string: "webkit-extension://abc/options.html")!, title: "Options")
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testUpdateTitleFillsLatestVisit() {
        var history = BrowsingHistory()
        history.recordVisit(url: a, title: nil)
        history.updateTitle("  Issue A ", for: a)
        XCTAssertEqual(history.entries[0].title, "Issue A")
        XCTAssertEqual(history.entries[0].displayTitle, "Issue A")
    }

    func testDisplayTitleFallsBackToHost() {
        XCTAssertEqual(HistoryEntry(url: a, title: "", date: Date()).displayTitle, "linear.app")
    }

    func testSearchMatchesAllWords() {
        var history = BrowsingHistory()
        history.recordVisit(url: a, title: "Fix login bug")
        history.recordVisit(url: b, title: "Roadmap")
        XCTAssertEqual(history.search("login team").map(\.url), [a])
        XCTAssertEqual(history.search("TEAM/B").map(\.url), [b])
        XCTAssertEqual(history.search("  ").count, 2)
    }

    func testCapsEntries() {
        var history = BrowsingHistory()
        for index in 0...BrowsingHistory.maxEntries {
            history.recordVisit(url: URL(string: "https://example.com/\(index)")!, title: nil)
        }
        XCTAssertEqual(history.entries.count, BrowsingHistory.maxEntries)
        XCTAssertEqual(history.entries.first?.url.path, "/\(BrowsingHistory.maxEntries)")
    }

    func testRemove() {
        var history = BrowsingHistory()
        history.recordVisit(url: a, title: "A")
        history.recordVisit(url: b, title: "B")
        history.remove([history.entries[0].id])
        XCTAssertEqual(history.entries.map(\.url), [a])
        history.removeAll()
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testSaveAndLoad() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("history.json")
        XCTAssertEqual(try BrowsingHistory.load(from: file), BrowsingHistory())

        var history = BrowsingHistory()
        history.recordVisit(url: a, title: "A", date: Date(timeIntervalSince1970: 1_700_000_000))
        try history.save(to: file)
        XCTAssertEqual(try BrowsingHistory.load(from: file), history)
    }
}
