import Foundation

/// The app name field accepts a path: "WebWrap/Photos" names the app "Photos"
/// and puts it in the "WebWrap" subfolder of Applications.
public struct AppLocation: Equatable {
    public let folders: [String]
    public let name: String

    public init(_ input: String) {
        let parts = input
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        self.name = parts.last ?? ""
        self.folders = parts.dropLast().map(InputNormalizer.fileSafeName)
    }

    /// Where the app bundle goes, under `root` (normally /Applications).
    public func bundleURL(in root: URL) -> URL {
        let folder = folders.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
        return folder.appendingPathComponent(InputNormalizer.fileSafeName(name) + ".app")
    }
}
