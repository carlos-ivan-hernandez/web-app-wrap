import Foundation

/// Decides whether a URL belongs to the wrapped web app or should go to the browser.
/// The app's own site is the base URL's host; `allowedDomains` adds other sites the user
/// allowed (each with its subdomains).
public struct LinkPolicy {
    public let baseURL: URL
    private let baseHost: String
    private let allowedHosts: [String]

    public init(baseURL: URL, allowedDomains: [String] = []) {
        self.baseURL = baseURL
        self.baseHost = Self.canonicalHost(baseURL.host ?? "")
        self.allowedHosts = allowedDomains.compactMap(Self.normalizeDomain)
    }

    /// The domain in a typed or pasted entry: "Example.com", "www.example.com" and
    /// "https://example.com/page" all give "example.com". nil if it isn't a web address.
    public static func normalizeDomain(_ input: String) -> String? {
        guard let host = InputNormalizer.normalizeURL(input)?.host, !host.isEmpty else { return nil }
        let canonical = canonicalHost(host)
        return canonical.isEmpty ? nil : canonical
    }

    /// The domain a URL would be allowed under, for offering to allow it.
    public static func domain(of url: URL) -> String? {
        url.host.map(canonicalHost).flatMap { $0.isEmpty ? nil : $0 }
    }

    public enum Destination: Equatable {
        /// Load inside the app.
        case app
        /// Open in the default web browser.
        case browser
        /// Hand to whatever app handles the scheme (mailto:, tel:, zoommtg:, ...).
        case system
    }

    public func destination(for url: URL) -> Destination {
        guard let scheme = url.scheme?.lowercased() else { return .app }
        switch scheme {
        case "about", "blob", "data", "javascript", "webkit-extension":
            // webkit-extension: pages that belong to a browser extension, such as its options.
            return .app
        case "http", "https":
            return isInternalHost(url.host) ? .app : .browser
        default:
            return .system
        }
    }

    public func isInternal(_ url: URL) -> Bool {
        destination(for: url) == .app
    }

    /// Same host as the base URL or an allowed domain, or a subdomain of one. "www." is
    /// ignored on both sides.
    private func isInternalHost(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        let candidate = Self.canonicalHost(host)
        return ([baseHost] + allowedHosts).contains { candidate == $0 || candidate.hasSuffix("." + $0) }
    }

    private static func canonicalHost(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }
}
