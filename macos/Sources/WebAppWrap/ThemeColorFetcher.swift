import Foundation
import WebAppWrapKit

/// Downloads a page and returns its theme color, checking the HTML first and then the
/// web app manifest it links to (single-page apps often declare it only there).
enum ThemeColorFetcher {
    static func fetch(from url: URL) async -> HexColor? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        guard let page = try? await URLSession.shared.data(for: request) else { return nil }
        let html = String(decoding: page.0, as: UTF8.self)
        if let color = ThemeColor.fromHTML(html) { return color }

        guard let manifestURL = ThemeColor.manifestURL(inHTML: html, pageURL: page.1.url ?? url),
              let manifest = try? await URLSession.shared.data(from: manifestURL)
        else { return nil }
        return ThemeColor.fromManifest(manifest.0)
    }
}
