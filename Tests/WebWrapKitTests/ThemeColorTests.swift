import XCTest
@testable import WebWrapKit

final class ThemeColorTests: XCTestCase {
    func testMultilineMetaTag() {
        let html = """
        <head>
            <meta
              name="theme-color"
              content="#1a1a1a"
            />
        </head>
        """
        XCTAssertEqual(ThemeColor.fromHTML(html)?.hexString, "#1A1A1A")
    }

    func testAttributeOrderQuotesAndCase() {
        XCTAssertEqual(ThemeColor.fromHTML("<META content='#FFF' NAME=theme-color>")?.hexString, "#FFFFFF")
    }

    func testPrefersTagWithoutMediaThenLight() {
        let html = """
        <meta name="theme-color" media="(prefers-color-scheme: dark)" content="#000000">
        <meta name="theme-color" media="(prefers-color-scheme: light)" content="#eeeeee">
        """
        XCTAssertEqual(ThemeColor.fromHTML(html)?.hexString, "#EEEEEE")
        XCTAssertEqual(ThemeColor.fromHTML(html + ##"<meta name="theme-color" content="#123456">"##)?.hexString, "#123456")
    }

    func testNoThemeColor() {
        XCTAssertNil(ThemeColor.fromHTML(##"<meta name="description" content="#abcdef">"##))
        XCTAssertNil(ThemeColor.fromHTML(#"<meta name="theme-color" content="var(--brand)">"#))
    }

    func testManifestLink() {
        let page = URL(string: "https://kphotos.vercel.app/login")!
        let html = #"<link rel="icon" href="/icon.svg"><link rel="manifest" href="/manifest.webmanifest">"#
        XCTAssertEqual(
            ThemeColor.manifestURL(inHTML: html, pageURL: page)?.absoluteString,
            "https://kphotos.vercel.app/manifest.webmanifest"
        )
        XCTAssertNil(ThemeColor.manifestURL(inHTML: #"<link rel="icon" href="/a.png">"#, pageURL: page))
    }

    func testManifestThemeColor() {
        let data = Data(##"{"name":"Photos","theme_color":"#1a1a1a","background_color":"#000"}"##.utf8)
        XCTAssertEqual(ThemeColor.fromManifest(data)?.hexString, "#1A1A1A")
        XCTAssertNil(ThemeColor.fromManifest(Data("{}".utf8)))
    }

    func testCSSForms() {
        XCTAssertEqual(HexColor(css: "#1a1a1aff")?.hexString, "#1A1A1A")
        XCTAssertEqual(HexColor(css: "#abcd")?.hexString, "#AABBCC")
        XCTAssertEqual(HexColor(css: "rgb(26, 26, 26)")?.hexString, "#1A1A1A")
        XCTAssertEqual(HexColor(css: "rgba(255,0,0,0.5)")?.hexString, "#FF0000")
        XCTAssertEqual(HexColor(css: "rgb(100% 0% 0% / 50%)")?.hexString, "#FF0000")
        XCTAssertEqual(HexColor(css: "White")?.hexString, "#FFFFFF")
        XCTAssertNil(HexColor(css: "hsl(0, 0%, 10%)"))
    }
}
