import AppKit
import WebAppWrapKit

/// Builds every app in a batch file, one at a time, carrying on past failures.
enum BatchBuilder {
    struct Result {
        let entry: BatchEntry
        let outcome: Swift.Result<URL, Error>
    }

    struct UnreadableImage: LocalizedError {
        let path: String
        var errorDescription: String? { "Couldn’t read an image from \(path)." }
    }

    /// The same choices the window makes: automatic icon zoom times the entry's zoom, and the
    /// site's theme color unless the entry names a color.
    static func spec(for entry: BatchEntry, appID: UUID? = nil) async throws -> AppSpec {
        var icon = IconSource.generated(name: entry.location.name)
        if let imageURL = entry.image {
            guard let image = NSImage(contentsOf: imageURL), image.isValid else {
                throw UnreadableImage(path: imageURL.path)
            }
            icon = .image(image, zoom: IconRenderer.automaticZoom(for: image) * CGFloat(entry.zoom))
        }
        var titleBarColor = HexColor.defaultTitleBar
        if let chosen = entry.titleBarColor {
            titleBarColor = chosen
        } else if let siteColor = await ThemeColorFetcher.fetch(from: entry.url) {
            titleBarColor = siteColor
        }
        return AppSpec(displayName: entry.location.name, baseURL: entry.url, icon: icon, titleBarColor: titleBarColor, appID: appID)
    }

    /// `progress` is called before each app with its zero-based index. `appIDs`, if given,
    /// has each entry's ID in WebAppWrap's list.
    static func run(
        _ entries: [BatchEntry],
        appIDs: [UUID]? = nil,
        into root: URL,
        progress: @escaping (Int, BatchEntry) async -> Void = { _, _ in }
    ) async -> [Result] {
        var results: [Result] = []
        for (index, entry) in entries.enumerated() {
            await progress(index, entry)
            do {
                let spec = try await spec(for: entry, appID: appIDs?[index])
                let app = try AppBuilder.build(spec, to: entry.location.bundleURL(in: root))
                results.append(Result(entry: entry, outcome: .success(app)))
            } catch {
                results.append(Result(entry: entry, outcome: .failure(error)))
            }
        }
        return results
    }
}
