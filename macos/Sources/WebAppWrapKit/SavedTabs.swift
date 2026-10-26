import CoreGraphics
import Foundation

/// The windows and tabs a wrapped app had open, so it can reopen them at its next launch.
/// Each app keeps its own, in ~/Library/Application Support/<bundle ID>/tabs.json.
public struct SavedTabs: Codable, Equatable {
    public struct Window: Codable, Equatable {
        /// The profile whose logins the window used.
        public var profile: UUID
        public var tabs: [URL]
        /// Index into `tabs` of the tab that was showing.
        public var selected: Int
        public var frame: CGRect?

        public init(profile: UUID, tabs: [URL], selected: Int, frame: CGRect? = nil) {
            self.profile = profile
            self.tabs = tabs
            self.selected = selected
            self.frame = frame
        }
    }

    /// Front window first.
    public var windows: [Window]

    public init(windows: [Window] = []) {
        self.windows = windows
    }

    /// What can be reopened now: web pages on sites the app still allows, in profiles that
    /// still exist. Windows left with no tabs are dropped, and each window's selected tab
    /// follows the tabs that remain.
    public func reopenable(isAllowed: (URL) -> Bool, profileExists: (UUID) -> Bool) -> SavedTabs {
        SavedTabs(windows: windows.compactMap { window in
            guard profileExists(window.profile) else { return nil }
            var kept: [URL] = []
            var selected = 0
            for (index, url) in window.tabs.enumerated() where BrowsingHistory.isRecordable(url) && isAllowed(url) {
                if index <= window.selected { selected = kept.count }
                kept.append(url)
            }
            guard !kept.isEmpty else { return nil }
            return Window(profile: window.profile, tabs: kept, selected: selected, frame: window.frame)
        })
    }

    /// Nothing saved if the file is missing or unreadable.
    public static func load(from file: URL) -> SavedTabs {
        guard let data = try? Data(contentsOf: file) else { return SavedTabs() }
        return (try? JSONDecoder().decode(SavedTabs.self, from: data)) ?? SavedTabs()
    }

    public func save(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: file, options: .atomic)
    }
}
