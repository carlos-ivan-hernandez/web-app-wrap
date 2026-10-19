import Foundation

/// Turns loosely typed user input into the values a generated app needs.
public enum InputNormalizer {
    // Letters (including IDN), digits, and the punctuation valid in hostnames and IPv6 literals.
    // Rejects spaces and percent-escapes that newer Foundation versions produce for bad input.
    private static let hostCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._:[]"))

    /// Accepts "example.com", "https://example.com/app", "localhost:3000", etc.
    /// Returns nil unless the result is an http(s) URL with a host.
    public static func normalizeURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if !text.contains("://") {
            let lower = text.lowercased()
            let isLocal = lower.hasPrefix("localhost") || lower.hasPrefix("127.0.0.1") || lower.hasPrefix("0.0.0.0")
            text = (isLocal ? "http://" : "https://") + text
        }

        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              host.unicodeScalars.allSatisfy(hostCharacters.contains)
        else { return nil }

        return components.url
    }

    /// Lowercase ASCII slug: "My Cool App!" -> "my-cool-app". Never empty.
    public static func slug(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        var result = ""
        var pendingHyphen = false
        for scalar in folded.unicodeScalars {
            let isAlnum = (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
            if isAlnum {
                if pendingHyphen && !result.isEmpty { result.append("-") }
                result.unicodeScalars.append(scalar)
                pendingHyphen = false
            } else {
                pendingHyphen = true
            }
        }
        return result.isEmpty ? "app" : result
    }

    /// Stable bundle identifier for a wrapped app. Cookies and local storage are
    /// keyed by this, so regenerating an app with the same name keeps its sessions.
    public static func bundleIdentifier(for name: String) -> String {
        "com.webwrap.app." + slug(name)
    }

    /// A display name that is safe to use as a file name (no "/" or ":").
    public static func fileSafeName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutLeadingDot = cleaned.hasPrefix(".") ? String(cleaned.dropFirst()) : cleaned
        return withoutLeadingDot.isEmpty ? "App" : withoutLeadingDot
    }
}
