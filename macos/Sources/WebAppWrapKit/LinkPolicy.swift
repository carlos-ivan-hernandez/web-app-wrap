import Foundation

/// Decides whether a URL belongs to the wrapped web app or should go to the browser.
public struct LinkPolicy {
    public let baseURL: URL
    private let baseHost: String

    public init(baseURL: URL) {
        self.baseURL = baseURL
        self.baseHost = Self.canonicalHost(baseURL.host ?? "")
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

    /// Same host as the base URL, or a subdomain of it. "www." is ignored on both sides.
    private func isInternalHost(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        let candidate = Self.canonicalHost(host)
        return candidate == baseHost || candidate.hasSuffix("." + baseHost)
    }

    private static func canonicalHost(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }
}
