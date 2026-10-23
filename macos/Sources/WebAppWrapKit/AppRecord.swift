import Foundation

/// What an app in the list is made from. The same inputs as the window and a batch entry,
/// except that the icon is a file WebAppWrap keeps in its own icons folder (see AppRegistry).
public struct AppSettings: Codable, Equatable {
    /// May include folders under the apps folder, as in the window: "WebAppWrap/Photos".
    public var name: String
    public var url: String
    /// File name in AppRegistry's icons folder. nil draws the default icon.
    public var icon: String?
    /// For an SVG icon, 0.5–3, where 1 fits the whole SVG in the icon. For other images (icons
    /// saved before SVG support), 1–3 on top of the automatic zoom that crops off a border.
    public var zoom: Double
    /// "#RRGGBB" behind an SVG icon. nil uses HexColor.defaultIconBackground.
    public var iconBackground: String?
    /// "#RRGGBB" an SVG icon is filled with. nil keeps the SVG's own colors.
    public var iconColor: String?
    /// "#RRGGBB". nil uses the site's theme color.
    public var titleBarColor: String?

    public init(name: String, url: String, icon: String? = nil, zoom: Double = 1, iconBackground: String? = nil, iconColor: String? = nil, titleBarColor: String? = nil) {
        self.name = name
        self.url = url
        self.icon = icon
        self.zoom = zoom
        self.iconBackground = iconBackground
        self.iconColor = iconColor
        self.titleBarColor = titleBarColor
    }

    public var location: AppLocation { AppLocation(name) }
}

/// When an app was last built, by which WebAppWrap, and from which settings.
public struct BuildStamp: Codable, Equatable {
    /// The commit WebAppWrap was built from (see GeneratorVersion). nil for development builds.
    public var version: String?
    public var date: Date
    public var settings: AppSettings

    public init(version: String?, date: Date, settings: AppSettings) {
        self.version = version
        self.date = date
        self.settings = settings
    }
}

/// One app in the list WebAppWrap keeps of the apps it has created.
public struct AppRecord: Codable, Equatable, Identifiable {
    public var id: UUID
    public var settings: AppSettings
    public var lastBuild: BuildStamp?

    public init(id: UUID = UUID(), settings: AppSettings, lastBuild: BuildStamp? = nil) {
        self.id = id
        self.settings = settings
        self.lastBuild = lastBuild
    }

    /// Why the app needs building, or nil if it's up to date and can be skipped.
    public enum BuildReason: Equatable {
        case neverBuilt
        case changed
        case newVersion
        /// This WebAppWrap has no version (e.g. `swift run`), so nothing counts as up to date.
        case unknownVersion
        case missing

        public var description: String {
            switch self {
            case .neverBuilt: "Not built yet"
            case .changed: "Changed since the last build"
            case .newVersion: "Built with another version of WebAppWrap"
            case .unknownVersion: "This WebAppWrap has no version, so it always rebuilds"
            case .missing: "The app isn’t in the apps folder"
            }
        }
    }

    /// An app is skipped only when its settings and the WebAppWrap version match its last
    /// build, and the app is still where it was built.
    public func buildReason(currentVersion: String?, appExists: Bool) -> BuildReason? {
        guard let lastBuild else { return .neverBuilt }
        if lastBuild.settings != settings { return .changed }
        guard let currentVersion else { return .unknownVersion }
        if lastBuild.version != currentVersion { return .newVersion }
        if !appExists { return .missing }
        return nil
    }

    /// The same inputs as a batch-file entry, so the list builds exactly like a batch.
    public func batchEntry(iconsFolder: URL) -> BatchEntry? {
        guard let url = InputNormalizer.normalizeURL(settings.url) else { return nil }
        return BatchEntry(
            location: settings.location,
            url: url,
            image: settings.icon.map { iconsFolder.appendingPathComponent($0) },
            zoom: settings.zoom,
            iconBackground: settings.iconBackground.flatMap(HexColor.init(hex:)),
            iconColor: settings.iconColor.flatMap(HexColor.init(hex:)),
            titleBarColor: settings.titleBarColor.flatMap(HexColor.init(hex:))
        )
    }
}

extension AppLocation {
    /// Case-insensitive, like the macOS file system: "Photos" and "photos" are the same app.
    public var key: String {
        bundleURL(in: URL(fileURLWithPath: "/")).path.lowercased()
    }
}
