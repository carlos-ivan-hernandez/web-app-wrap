import XCTest
@testable import WebAppWrapKit

final class StaleScriptTests: XCTestCase {
    func testMissingScripts() {
        XCTAssertTrue(StaleScript.isMissing(statusCode: 404, mimeType: "text/html"))
        XCTAssertTrue(StaleScript.isMissing(statusCode: 410, mimeType: nil))
        // An SPA rewrite answers a missing file with its index.html.
        XCTAssertTrue(StaleScript.isMissing(statusCode: 200, mimeType: "text/html"))
        XCTAssertTrue(StaleScript.isMissing(statusCode: 200, mimeType: "TEXT/HTML"))
    }

    func testScriptsThatAreThere() {
        XCTAssertFalse(StaleScript.isMissing(statusCode: 200, mimeType: "text/javascript"))
        XCTAssertFalse(StaleScript.isMissing(statusCode: 200, mimeType: "application/javascript"))
        XCTAssertFalse(StaleScript.isMissing(statusCode: 304, mimeType: nil))
        // Server trouble isn't a sign of an old page.
        XCTAssertFalse(StaleScript.isMissing(statusCode: 500, mimeType: "text/html"))
        XCTAssertFalse(StaleScript.isMissing(statusCode: 403, mimeType: "text/html"))
    }

    func testRecordNames() {
        XCTAssertTrue(StaleScript.record(named: "k-vera.vercel.app", covers: "k-vera.vercel.app"))
        XCTAssertTrue(StaleScript.record(named: "example.com", covers: "app.example.com"))
        XCTAssertTrue(StaleScript.record(named: "Example.com", covers: "APP.example.com"))
        XCTAssertFalse(StaleScript.record(named: "example.com", covers: "notexample.com"))
        XCTAssertFalse(StaleScript.record(named: "app.example.com", covers: "example.com"))
        XCTAssertFalse(StaleScript.record(named: "", covers: "example.com"))
    }

    func testScriptURLInMessage() {
        let message = "'text/html' is not a valid JavaScript MIME type for module script 'https://k-vera.vercel.app/assets/index-DT84fB81.js'."
        XCTAssertEqual(
            StaleScript.scriptURL(inErrorMessage: message)?.absoluteString,
            "https://k-vera.vercel.app/assets/index-DT84fB81.js"
        )
        XCTAssertNil(StaleScript.scriptURL(inErrorMessage: "Importing a module script failed."))
    }
}
