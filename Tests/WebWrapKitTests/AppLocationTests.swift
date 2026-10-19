import XCTest
@testable import WebWrapKit

final class AppLocationTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Applications")

    func testPlainName() {
        let location = AppLocation("Photos")
        XCTAssertEqual(location.name, "Photos")
        XCTAssertEqual(location.folders, [])
        XCTAssertEqual(location.bundleURL(in: root).path, "/Applications/Photos.app")
    }

    func testSubfolder() {
        let location = AppLocation("WebWrap/Photos")
        XCTAssertEqual(location.name, "Photos")
        XCTAssertEqual(location.folders, ["WebWrap"])
        XCTAssertEqual(location.bundleURL(in: root).path, "/Applications/WebWrap/Photos.app")
    }

    func testIgnoresEmptyAndRelativeParts() {
        let location = AppLocation(" /Web Wrap// ../ Photos ")
        XCTAssertEqual(location.name, "Photos")
        XCTAssertEqual(location.bundleURL(in: root).path, "/Applications/Web Wrap/Photos.app")
    }

    func testTrailingSlashHasNoName() {
        XCTAssertEqual(AppLocation("WebWrap/").name, "WebWrap")
        XCTAssertEqual(AppLocation("   ").name, "")
    }
}
