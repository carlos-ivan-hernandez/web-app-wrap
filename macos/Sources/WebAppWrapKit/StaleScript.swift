import Foundation

/// Decisions for recovering a page that's an old copy of a site: after the site is updated,
/// its service worker can keep serving the old page, whose scripts the server no longer has.
public enum StaleScript {
    /// Whether the server's answer for a script means the script is gone: a 404 or 410, or an
    /// HTML page in its place (sites that send every unknown path to index.html).
    public static func isMissing(statusCode: Int, mimeType: String?) -> Bool {
        if statusCode == 404 || statusCode == 410 { return true }
        guard (200..<300).contains(statusCode) else { return false }
        return mimeType?.lowercased() == "text/html"
    }

    /// Whether a website data record, named after its site ("example.com"), holds data for
    /// `host` ("app.example.com").
    public static func record(named name: String, covers host: String) -> Bool {
        let name = name.lowercased()
        let host = host.lowercased()
        guard !name.isEmpty, !host.isEmpty else { return false }
        return host == name || host.hasSuffix("." + name)
    }

    /// The script a failed module import names, from WebKit's message:
    /// "'text/html' is not a valid JavaScript MIME type for module script 'https://…/index.js'".
    public static func scriptURL(inErrorMessage message: String) -> URL? {
        guard let range = message.range(of: #"'(https?://[^']+)'"#, options: .regularExpression) else { return nil }
        return URL(string: String(message[range].dropFirst().dropLast()))
    }
}
