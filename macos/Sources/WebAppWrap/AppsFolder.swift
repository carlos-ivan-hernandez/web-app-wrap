import Foundation

/// The folder WebAppWrap saves apps in: /Applications unless you choose another in Settings.
/// It's also the command line's default for --out.
enum AppsFolder {
    /// In WebAppWrap's own defaults (com.waw.WebAppWrap). Missing means /Applications.
    static let defaultsKey = "AppsFolder"
    static let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)

    static var current: URL {
        guard let path = UserDefaults.standard.string(forKey: defaultsKey), !path.isEmpty else { return applications }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func set(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        if path == applications.path {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set(path, forKey: defaultsKey)
        }
    }

    /// For display, with "~" for the home folder.
    static func displayPath(_ folder: URL = current) -> String {
        (folder.path as NSString).abbreviatingWithTildeInPath
    }
}
