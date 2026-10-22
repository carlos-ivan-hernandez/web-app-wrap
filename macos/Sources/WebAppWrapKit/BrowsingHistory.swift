import Foundation

/// One page visit in a wrapped app.
public struct HistoryEntry: Codable, Equatable, Identifiable {
    public var id: UUID
    public var url: URL
    /// The page's title, or "" if it hasn't one (yet).
    public var title: String
    public var date: Date

    public init(id: UUID = UUID(), url: URL, title: String, date: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.date = date
    }

    /// The title, or the address when the page has no title.
    public var displayTitle: String {
        title.isEmpty ? (url.host ?? url.absoluteString) : title
    }
}

/// The pages a wrapped app has visited, newest first. Each app keeps its own, in
/// ~/Library/Application Support/<bundle ID>/history.json.
public struct BrowsingHistory: Equatable {
    /// Older visits are dropped past this many.
    public static let maxEntries = 5000

    public private(set) var entries: [HistoryEntry]

    public init(entries: [HistoryEntry] = []) {
        self.entries = entries
    }

    /// Only web pages are kept: not error pages, blank tabs or extension pages.
    public static func isRecordable(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return (scheme == "http" || scheme == "https") && url.host?.isEmpty == false
    }

    /// Adds a visit. Visiting the newest entry's page again (a reload, or a page that rewrites
    /// its address) updates that entry instead of adding another.
    public mutating func recordVisit(url: URL, title: String?, date: Date = Date()) {
        guard Self.isRecordable(url) else { return }
        let title = Self.clean(title)
        if !entries.isEmpty, entries[0].url == url {
            entries[0].date = date
            if !title.isEmpty { entries[0].title = title }
            return
        }
        entries.insert(HistoryEntry(url: url, title: title, date: date), at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }

    /// Pages often set their title after they load; this fills it into the latest visit.
    public mutating func updateTitle(_ title: String?, for url: URL) {
        let title = Self.clean(title)
        guard !title.isEmpty, let index = entries.firstIndex(where: { $0.url == url }) else { return }
        entries[index].title = title
    }

    public mutating func remove(_ ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
    }

    public mutating func removeAll() {
        entries = []
    }

    /// Entries whose title or address contains every word of `query`, ignoring case.
    /// An empty query matches everything.
    public func search(_ query: String) -> [HistoryEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            words.allSatisfy { word in
                entry.title.localizedCaseInsensitiveContains(word)
                    || entry.url.absoluteString.localizedCaseInsensitiveContains(word)
            }
        }
    }

    /// The latest visit to each of the most recently visited pages.
    public func recent(limit: Int) -> [HistoryEntry] {
        var seen = Set<URL>()
        var result: [HistoryEntry] = []
        for entry in entries where seen.insert(entry.url).inserted {
            result.append(entry)
            if result.count == limit { break }
        }
        return result
    }

    private static func clean(_ title: String?) -> String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - File

    private struct File: Codable {
        var entries: [HistoryEntry]
    }

    /// An empty history if the file doesn't exist yet.
    public static func load(from file: URL) throws -> BrowsingHistory {
        guard FileManager.default.fileExists(atPath: file.path) else { return BrowsingHistory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return BrowsingHistory(entries: try decoder.decode(File.self, from: Data(contentsOf: file)).entries)
    }

    public func save(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        try encoder.encode(File(entries: entries)).write(to: file, options: .atomic)
    }
}
