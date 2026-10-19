import Foundation

/// Finds a site's theme color: `<meta name="theme-color">` in its HTML, or `theme_color`
/// in the web app manifest the HTML links to.
public enum ThemeColor {
    /// The `content` of the first theme-color meta tag. Tags without a `media` query win over
    /// light/dark variants, and a light variant wins over a dark one.
    public static func fromHTML(_ html: String) -> HexColor? {
        let candidates = tags("meta", in: html)
            .filter { $0["name"]?.lowercased() == "theme-color" }
            .compactMap { tag -> (color: HexColor, rank: Int)? in
                guard let color = tag["content"].flatMap(HexColor.init(css:)) else { return nil }
                let media = tag["media"]?.lowercased() ?? ""
                let rank = media.isEmpty ? 0 : (media.contains("dark") ? 2 : 1)
                return (color, rank)
            }
        return candidates.min { $0.rank < $1.rank }?.color
    }

    /// The manifest linked from the HTML, resolved against the page's URL.
    public static func manifestURL(inHTML html: String, pageURL: URL) -> URL? {
        let link = tags("link", in: html).first { tag in
            (tag["rel"]?.lowercased().split(separator: " ").contains("manifest") ?? false) && tag["href"] != nil
        }
        return link?["href"].flatMap { URL(string: $0, relativeTo: pageURL)?.absoluteURL }
    }

    public static func fromManifest(_ data: Data) -> HexColor? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json["theme_color"] as? String
        else { return nil }
        return HexColor(css: value)
    }

    // MARK: - Minimal tag parsing (enough for <head> metadata, not a full HTML parser)

    private static let attributePattern = try! NSRegularExpression(
        pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#
    )

    /// Attributes of every `<name ...>` tag, with lowercased attribute names.
    private static func tags(_ name: String, in html: String) -> [[String: String]] {
        guard let tagPattern = try? NSRegularExpression(pattern: "<\(name)\\b[^>]*>", options: [.caseInsensitive]) else {
            return []
        }
        let text = html as NSString
        return tagPattern.matches(in: html, range: NSRange(location: 0, length: text.length)).map { match in
            let tag = text.substring(with: match.range)
            var attributes: [String: String] = [:]
            let tagText = tag as NSString
            for attribute in attributePattern.matches(in: tag, range: NSRange(location: 0, length: tagText.length)) {
                let key = tagText.substring(with: attribute.range(at: 1)).lowercased()
                let value = (2...4)
                    .map { attribute.range(at: $0) }
                    .first { $0.location != NSNotFound }
                    .map { tagText.substring(with: $0) } ?? ""
                attributes[key] = attributes[key] ?? value
            }
            return attributes
        }
    }
}

extension HexColor {
    /// Parses the CSS forms sites use for theme colors: #rgb, #rgba, #rrggbb, #rrggbbaa,
    /// rgb()/rgba() with numbers or percentages, and a few common names. Alpha is ignored.
    public init?(css: String) {
        let text = css.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch text {
        case "white": self.init(red: 1, green: 1, blue: 1); return
        case "black": self.init(red: 0, green: 0, blue: 0); return
        default: break
        }

        if text.hasPrefix("#") {
            var digits = String(text.dropFirst())
            if digits.count == 4 { digits = String(digits.prefix(3)) }
            if digits.count == 8 { digits = String(digits.prefix(6)) }
            self.init(hex: digits)
            return
        }

        guard text.hasPrefix("rgb"), let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")") else {
            return nil
        }
        let parts = text[text.index(after: open)..<close]
            .replacingOccurrences(of: "/", with: " ")
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map(String.init)
        guard parts.count >= 3 else { return nil }
        func channel(_ part: String) -> Double? {
            if part.hasSuffix("%") { return Double(part.dropLast()).map { $0 / 100 } }
            return Double(part).map { $0 / 255 }
        }
        guard let red = channel(parts[0]), let green = channel(parts[1]), let blue = channel(parts[2]) else { return nil }
        self.init(red: red, green: green, blue: blue)
    }
}
