import XCTest
@testable import WebAppWrapKit

final class BatchFileTests: XCTestCase {
    private let base = URL(fileURLWithPath: "/Users/me/apps")

    private func parse(_ json: String) throws -> [BatchEntry] {
        try BatchFile.parse(Data(json.utf8), baseDirectory: base)
    }

    private func errorMessage(_ json: String) -> String {
        do {
            _ = try parse(json)
            return "no error"
        } catch {
            return error.localizedDescription
        }
    }

    func testFullEntry() throws {
        let entries = try parse(##"""
        [{"name": "Web App Wrap/Photos", "url": "kphotos.vercel.app", "image": "icons/photos.png",
          "zoom": 1.5, "titleBarColor": "#1a1a1a"}]
        """##)
        XCTAssertEqual(entries.count, 1)
        let entry = entries[0]
        XCTAssertEqual(entry.location, AppLocation("Web App Wrap/Photos"))
        XCTAssertEqual(entry.url.absoluteString, "https://kphotos.vercel.app")
        XCTAssertEqual(entry.image?.path, "/Users/me/apps/icons/photos.png")
        XCTAssertEqual(entry.zoom, 1.5)
        XCTAssertEqual(entry.titleBarColor?.hexString, "#1A1A1A")
    }

    func testMinimalEntryUsesDefaults() throws {
        let entry = try parse(#"[{"name": "Linear", "url": "linear.app"}]"#)[0]
        XCTAssertNil(entry.image)
        XCTAssertEqual(entry.zoom, 1)
        XCTAssertNil(entry.titleBarColor)
    }

    func testAbsoluteAndParentImagePaths() throws {
        let entries = try parse(#"""
        [{"name": "A", "url": "a.com", "image": "/tmp/a.png"},
         {"name": "B", "url": "b.com", "image": "../shared/b.png"}]
        """#)
        XCTAssertEqual(entries[0].image?.path, "/tmp/a.png")
        XCTAssertEqual(entries[1].image?.path, "/Users/me/shared/b.png")
    }

    func testRejectsNonArray() {
        XCTAssertEqual(errorMessage(#"{"name": "A", "url": "a.com"}"#), "The file must contain a JSON array of app objects.")
        XCTAssertEqual(errorMessage("not json"), "The file isn’t valid JSON.")
        XCTAssertEqual(errorMessage("[]"), "The array is empty.")
    }

    func testReportsEveryProblemAtOnce() {
        let message = errorMessage(#"""
        [{"name": "Good", "url": "good.com"},
         {"url": "nameless.com"},
         {"name": "Bad", "url": "not a url", "zoom": 9, "titleBarColor": "teal", "icon": "x.png"},
         "oops"]
        """#)
        XCTAssertTrue(message.contains("Entry 2: “name” is missing."), message)
        XCTAssertTrue(message.contains("Entry 3 (Bad): unknown field “icon”"), message)
        XCTAssertTrue(message.contains("“url” is missing or isn’t a web address"), message)
        XCTAssertTrue(message.contains("“zoom” must be a number from 1 to 3"), message)
        XCTAssertTrue(message.contains("“titleBarColor” must be a color"), message)
        XCTAssertTrue(message.contains("Entry 4 isn’t an object."), message)
        XCTAssertFalse(message.contains("Entry 1"), message)
    }

    func testRejectsDuplicateDestinations() {
        let message = errorMessage(#"[{"name": "Photos", "url": "a.com"}, {"name": "photos", "url": "b.com"}]"#)
        XCTAssertTrue(message.contains("More than one entry would create photos.app"), message)
        XCTAssertEqual(errorMessage(#"[{"name": "A/Photos", "url": "a.com"}, {"name": "B/Photos", "url": "b.com"}]"#), "no error")
    }
}
