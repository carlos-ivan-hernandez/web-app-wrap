import Foundation

/// The list of apps WebAppWrap has created, and their icons. Everything lives in
/// ~/Library/Application Support/WebAppWrap:
///
///     apps.json         every app's settings and when it was last built
///     icons/            the image each app's icon is drawn from
///     previous-icons/   icons that were replaced or removed, kept in case they're wanted again
public struct AppRegistry {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public static var standard: AppRegistry {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppRegistry(folder: support.appendingPathComponent("WebAppWrap", isDirectory: true))
    }

    public var listFile: URL { folder.appendingPathComponent("apps.json") }
    public var iconsFolder: URL { folder.appendingPathComponent("icons", isDirectory: true) }
    public var previousIconsFolder: URL { folder.appendingPathComponent("previous-icons", isDirectory: true) }

    public func iconURL(_ fileName: String) -> URL {
        iconsFolder.appendingPathComponent(fileName)
    }

    // MARK: - The list

    private struct ListFile: Codable {
        var apps: [AppRecord]
    }

    /// An empty list if nothing has been saved yet.
    public func load() throws -> [AppRecord] {
        guard FileManager.default.fileExists(atPath: listFile.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ListFile.self, from: Data(contentsOf: listFile)).apps
    }

    public func save(_ records: [AppRecord]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(ListFile(apps: records)).write(to: listFile, options: .atomic)
    }

    // MARK: - Icons

    /// Copies `source` into the icons folder and returns its new file name. If it's the same
    /// image as `current`, returns `current` instead of making a copy.
    public func importIcon(from source: URL, for id: UUID, replacing current: String?) throws -> String {
        if let current {
            let currentURL = iconURL(current)
            if source.standardizedFileURL == currentURL.standardizedFileURL { return current }
            if let old = try? Data(contentsOf: currentURL), let new = try? Data(contentsOf: source), old == new {
                return current
            }
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: iconsFolder, withIntermediateDirectories: true)
        // A new name for every new image, so replacing an icon always changes the app's settings.
        let token = UUID().uuidString.prefix(8).lowercased()
        let ext = source.pathExtension.isEmpty ? "" : "." + source.pathExtension.lowercased()
        let fileName = "\(id.uuidString.lowercased())-\(token)\(ext)"
        try fileManager.copyItem(at: source, to: iconURL(fileName))
        return fileName
    }

    /// Moves an icon that's no longer used into previous-icons, named after the app and the time.
    @discardableResult
    public func retireIcon(_ fileName: String, appName: String, date: Date = Date()) throws -> URL? {
        let fileManager = FileManager.default
        let source = iconURL(fileName)
        guard fileManager.fileExists(atPath: source.path) else { return nil }
        try fileManager.createDirectory(at: previousIconsFolder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "\(InputNormalizer.fileSafeName(AppLocation(appName).name)) \(formatter.string(from: date))"
        let ext = source.pathExtension.isEmpty ? "" : "." + source.pathExtension

        var destination = previousIconsFolder.appendingPathComponent(base + ext)
        var counter = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = previousIconsFolder.appendingPathComponent("\(base) \(counter)\(ext)")
            counter += 1
        }
        try fileManager.moveItem(at: source, to: destination)
        return destination
    }
}
