import XCTest
@testable import WebWrapKit

final class LinkPolicyTests: XCTestCase {
    private let policy = LinkPolicy(baseURL: URL(string: "https://app.example.com/home")!)

    private func dest(_ s: String) -> LinkPolicy.Destination {
        policy.destination(for: URL(string: s)!)
    }

    func testSameHostIsInternal() {
        XCTAssertEqual(dest("https://app.example.com/settings"), .app)
        XCTAssertEqual(dest("http://APP.example.com"), .app)
        XCTAssertEqual(dest("https://www.app.example.com"), .app)
    }

    func testSubdomainIsInternal() {
        XCTAssertEqual(dest("https://eu.app.example.com/x"), .app)
    }

    func testOtherHostsGoToBrowser() {
        XCTAssertEqual(dest("https://example.com"), .browser)
        XCTAssertEqual(dest("https://github.com/foo"), .browser)
        XCTAssertEqual(dest("https://notapp.example.com"), .browser)
        XCTAssertEqual(dest("https://app.example.com.evil.io"), .browser)
    }

    func testNonWebSchemesGoToSystem() {
        XCTAssertEqual(dest("mailto:someone@example.com"), .system)
        XCTAssertEqual(dest("tel:5551234"), .system)
        XCTAssertEqual(dest("zoommtg://zoom.us/join"), .system)
    }

    func testInlineSchemesStayInApp() {
        XCTAssertEqual(dest("about:blank"), .app)
        XCTAssertEqual(dest("blob:https://app.example.com/abc"), .app)
    }

    func testWWWBase() {
        let p = LinkPolicy(baseURL: URL(string: "https://www.example.com")!)
        XCTAssertTrue(p.isInternal(URL(string: "https://example.com/a")!))
        XCTAssertTrue(p.isInternal(URL(string: "https://docs.example.com")!))
    }
}
