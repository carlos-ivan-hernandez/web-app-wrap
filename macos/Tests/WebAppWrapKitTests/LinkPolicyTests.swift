import XCTest
@testable import WebAppWrapKit

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
        XCTAssertEqual(dest("webkit-extension://dark-reader/options.html"), .app)
    }

    func testWWWBase() {
        let p = LinkPolicy(baseURL: URL(string: "https://www.example.com")!)
        XCTAssertTrue(p.isInternal(URL(string: "https://example.com/a")!))
        XCTAssertTrue(p.isInternal(URL(string: "https://docs.example.com")!))
    }

    func testAllowedDomainsAreInternal() {
        let allowed = LinkPolicy(baseURL: URL(string: "https://app.example.com")!, allowedDomains: ["github.com", "https://www.Notion.so/page"])
        XCTAssertEqual(allowed.destination(for: URL(string: "https://github.com/foo")!), .app)
        XCTAssertEqual(allowed.destination(for: URL(string: "https://gist.github.com/x")!), .app)
        XCTAssertEqual(allowed.destination(for: URL(string: "https://notion.so")!), .app)
        XCTAssertEqual(allowed.destination(for: URL(string: "https://github.com.evil.io")!), .browser)
        XCTAssertEqual(allowed.destination(for: URL(string: "https://gitlab.com")!), .browser)
    }

    func testNormalizeDomain() {
        XCTAssertEqual(LinkPolicy.normalizeDomain(" WWW.GitHub.com "), "github.com")
        XCTAssertEqual(LinkPolicy.normalizeDomain("https://linear.app/team/issue"), "linear.app")
        XCTAssertNil(LinkPolicy.normalizeDomain("not a domain"))
        XCTAssertNil(LinkPolicy.normalizeDomain(""))
        XCTAssertEqual(LinkPolicy.domain(of: URL(string: "https://www.figma.com/file")!), "figma.com")
    }

    func testAllowAllSites() {
        let open = LinkPolicy(baseURL: URL(string: "https://app.example.com")!, allowedDomains: ["github.com"], allowsAllSites: true)
        XCTAssertEqual(open.destination(for: URL(string: "https://gitlab.com/x")!), .app)
        XCTAssertEqual(open.destination(for: URL(string: "mailto:a@b.com")!), .system)
        XCTAssertFalse(open.isListed(URL(string: "https://gitlab.com/x")!))
        XCTAssertTrue(open.isListed(URL(string: "https://gist.github.com")!))
        XCTAssertTrue(open.isListed(URL(string: "https://app.example.com/home")!))
    }
}
