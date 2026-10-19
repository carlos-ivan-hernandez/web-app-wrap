import XCTest
@testable import WebAppWrapKit

final class InputNormalizerTests: XCTestCase {
    func testAddsHTTPSWhenSchemeMissing() {
        XCTAssertEqual(InputNormalizer.normalizeURL("example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(InputNormalizer.normalizeURL("  app.example.com/dashboard ")?.absoluteString, "https://app.example.com/dashboard")
    }

    func testLocalhostDefaultsToHTTP() {
        XCTAssertEqual(InputNormalizer.normalizeURL("localhost:3000")?.absoluteString, "http://localhost:3000")
        XCTAssertEqual(InputNormalizer.normalizeURL("127.0.0.1:8080/x")?.absoluteString, "http://127.0.0.1:8080/x")
    }

    func testKeepsExplicitScheme() {
        XCTAssertEqual(InputNormalizer.normalizeURL("http://example.com")?.absoluteString, "http://example.com")
    }

    func testRejectsInvalid() {
        XCTAssertNil(InputNormalizer.normalizeURL(""))
        XCTAssertNil(InputNormalizer.normalizeURL("   "))
        XCTAssertNil(InputNormalizer.normalizeURL("ftp://example.com"))
        XCTAssertNil(InputNormalizer.normalizeURL("not a url"))
        XCTAssertNil(InputNormalizer.normalizeURL("https://"))
    }

    func testSlug() {
        XCTAssertEqual(InputNormalizer.slug("My Cool App!"), "my-cool-app")
        XCTAssertEqual(InputNormalizer.slug("  Café   Crème "), "cafe-creme")
        XCTAssertEqual(InputNormalizer.slug("🚀"), "app")
        XCTAssertEqual(InputNormalizer.slug("A--B"), "a-b")
    }

    func testBundleIdentifier() {
        XCTAssertEqual(InputNormalizer.bundleIdentifier(for: "Linear"), "com.waw.app.linear")
    }

    func testFileSafeName() {
        XCTAssertEqual(InputNormalizer.fileSafeName("A/B:C"), "A-B-C")
        XCTAssertEqual(InputNormalizer.fileSafeName(".hidden"), "hidden")
        XCTAssertEqual(InputNormalizer.fileSafeName("  "), "App")
    }
}
