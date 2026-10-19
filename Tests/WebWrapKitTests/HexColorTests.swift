import XCTest
@testable import WebWrapKit

final class HexColorTests: XCTestCase {
    func testParsesLongAndShortForms() {
        XCTAssertEqual(HexColor(hex: "#1a1a1a")?.hexString, "#1A1A1A")
        XCTAssertEqual(HexColor(hex: "FF8000")?.hexString, "#FF8000")
        XCTAssertEqual(HexColor(hex: " #fff ")?.hexString, "#FFFFFF")
    }

    func testRejectsInvalid() {
        XCTAssertNil(HexColor(hex: ""))
        XCTAssertNil(HexColor(hex: "#12345"))
        XCTAssertNil(HexColor(hex: "#GGGGGG"))
    }

    func testRoundTripsComponents() {
        let color = HexColor(red: 0.5, green: 0.25, blue: 1)
        XCTAssertEqual(HexColor(hex: color.hexString)?.hexString, color.hexString)
        XCTAssertEqual(color.hexString, "#8040FF")
    }

    func testDarkness() {
        XCTAssertTrue(HexColor.defaultTitleBar.isDark)
        XCTAssertTrue(HexColor(hex: "#000")!.isDark)
        XCTAssertFalse(HexColor(hex: "#fff")!.isDark)
        XCTAssertFalse(HexColor(hex: "#f2f2f2")!.isDark)
    }
}
