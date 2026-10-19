import XCTest
@testable import WebAppWrapKit

final class AppLocationTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Applications")

    func testPlainName() {
        let location = AppLocation("Photos")
        XCTAssertEqual(location.name, "Photos")
        XCTAssertEqual(location.folders, [])
        XCTAssertEqual(location.bundleURL(in: root).path, "/Applications/Photos.app")
    }

    func testSubfolder() {
        let location = AppLocation("Web App Wrap/Photos")
        XCTAssertEqual(location.name, "Photos")
        XCTAssertEqual(location.folders, ["Web App Wrap"])
        XCTAssertEqual(location.bundleURL(in: root).path, "/Applications/Web App Wrap/Photos.app")
    }

    func testIgnoresEmptyAndRelativeParts() {
        let location = AppLocation(" /Web Wrap// ../ Photos ")
        XCTAssertEqual(location.name, "Photos")
        XCTAssertEqual(location.bundleURL(in: root).path, "/Applications/Web Wrap/Photos.app")
    }

    func testTrailingSlashHasNoName() {
        XCTAssertEqual(AppLocation("Web App Wrap/").name, "Web App Wrap")
        XCTAssertEqual(AppLocation("   ").name, "")
    }
}
