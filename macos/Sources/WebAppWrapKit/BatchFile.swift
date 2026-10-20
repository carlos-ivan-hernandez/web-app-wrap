import Foundation

/// One app in a batch file. The fields mirror the WebAppWrap window:
///
///     [
///       {
///         "name": "WebAppWrap/Photos",
///         "url": "https://kphotos.vercel.app",
///         "image": "icons/photos.png",
///         "zoom": 1.2,
///         "titleBarColor": "#1a1a1a"
///       }
///     ]
///
/// Only `name` and `url` are required. `name` may include folders, as in the window.
/// `image` is a path, relative to the batch file unless absolute (`~` works).
/// `zoom` (1–3) is on top of the automatic zoom that crops off a border.
/// `titleBarColor` defaults to the site's theme color.
/// The file may be JSON, JSONC or JSON5 (comments, trailing commas, unquoted keys and so on).
public struct BatchEntry: Equatable {
    public let location: AppLocation
    public let url: URL
    public let image: URL?
    public let zoom: Double
    public let titleBarColor: HexColor?

    public init(location: AppLocation, url: URL, image: URL?, zoom: Double, titleBarColor: HexColor?) {
        self.location = location
        self.url = url
        self.image = image
        self.zoom = zoom
        self.titleBarColor = titleBarColor
    }
}

public enum BatchFile {
    public struct ParseError: LocalizedError, Equatable {
        public let message: String
        public var errorDescription: String? { message }
    }

    public static let zoomRange: ClosedRange<Double> = 1...3

    /// File extensions offered when choosing a batch file.
    public static let fileExtensions = ["json", "jsonc", "json5"]

    /// Reads every entry, or fails with one message listing every problem found
    /// (so a batch never half-runs because of a typo in its last entry).
    public static func parse(_ data: Data, baseDirectory: URL) throws -> [BatchEntry] {
        // JSON5 is a superset of JSONC and JSON, so one reader covers all three.
        guard let json = try? JSONSerialization.jsonObject(with: data, options: .json5Allowed) else {
            throw ParseError(message: "The file isn’t valid JSON.")
        }
        guard let objects = json as? [Any] else {
            throw ParseError(message: "The file must contain a JSON array of app objects.")
        }
        guard !objects.isEmpty else {
            throw ParseError(message: "The array is empty.")
        }

        var entries: [BatchEntry] = []
        var problems: [String] = []
        let knownKeys: Set<String> = ["name", "url", "image", "zoom", "titleBarColor"]

        for (index, element) in objects.enumerated() {
            let label = "Entry \(index + 1)"
            guard let object = element as? [String: Any] else {
                problems.append("\(label) isn’t an object.")
                continue
            }
            let entryLabel = (object["name"] as? String).map { "\(label) (\($0))" } ?? label
            var entryProblems: [String] = []

            let unknown = Set(object.keys).subtracting(knownKeys).sorted()
            if !unknown.isEmpty {
                entryProblems.append("unknown field\(unknown.count == 1 ? "" : "s") \(unknown.map { "“\($0)”" }.joined(separator: ", "))")
            }

            let location = AppLocation(object["name"] as? String ?? "")
            if location.name.isEmpty { entryProblems.append("“name” is missing") }

            let url = (object["url"] as? String).flatMap(InputNormalizer.normalizeURL)
            if url == nil { entryProblems.append("“url” is missing or isn’t a web address") }

            var image: URL?
            if let value = object["image"] {
                if let path = value as? String, !path.trimmingCharacters(in: .whitespaces).isEmpty {
                    let expanded = (path as NSString).expandingTildeInPath
                    image = expanded.hasPrefix("/")
                        ? URL(fileURLWithPath: expanded)
                        : baseDirectory.appendingPathComponent(expanded).standardizedFileURL
                } else if !(value is NSNull) {
                    entryProblems.append("“image” must be a file path")
                }
            }

            var zoom = 1.0
            if let value = object["zoom"], !(value is NSNull) {
                if let number = (value as? Double) ?? (value as? Int).map(Double.init), zoomRange.contains(number) {
                    zoom = number
                } else {
                    entryProblems.append("“zoom” must be a number from 1 to 3")
                }
            }

            var titleBarColor: HexColor?
            if let value = object["titleBarColor"], !(value is NSNull) {
                titleBarColor = (value as? String).flatMap(HexColor.init(css:))
                if titleBarColor == nil { entryProblems.append("“titleBarColor” must be a color like \"#1a1a1a\"") }
            }

            if let url, entryProblems.isEmpty {
                entries.append(BatchEntry(location: location, url: url, image: image, zoom: zoom, titleBarColor: titleBarColor))
            } else {
                problems.append("\(entryLabel): \(entryProblems.joined(separator: "; ")).")
            }
        }

        let destinations = entries.map(\.location.key)
        let duplicates = Dictionary(grouping: destinations, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        for duplicate in duplicates {
            problems.append("More than one entry would create \(duplicate.dropFirst()).")
        }

        guard problems.isEmpty else {
            throw ParseError(message: problems.joined(separator: "\n"))
        }
        return entries
    }
}
