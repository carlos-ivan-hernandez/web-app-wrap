import AppKit
import WebAppWrapKit

/// Scriptable entry points; see `usage`.
enum CommandLineInterface {
    static let usage = """
    Usage:
      WebAppWrap
          Open the app.

      WebAppWrap build --name <name> --url <address> [--image <file>] [--zoom <1-3>] [--no-auto-zoom]
                    [--title-bar-color <#RRGGBB>] [--out <folder>]
          Create one app. <name> may include folders, e.g. "WebAppWrap/Photos".
          --zoom adds to the automatic zoom that crops off an image's border.
          --no-auto-zoom uses the image as it is, border and all.
          The title bar color defaults to the site's theme color.
          --out is the folder apps go in (default: the folder chosen in WebAppWrap's
          Settings, or /Applications).

      WebAppWrap batch <file.json> [--out <folder>]
          Create every app listed in a JSON array of objects with the fields
          name, url, image, zoom and titleBarColor (only name and url are required).
          JSONC and JSON5 (comments, trailing commas, unquoted keys) work too.
          Apps built from the command line aren't added to the window's My Apps list.

      WebAppWrap icon --name <name> [--symbol <sf-symbol>] [--image <file>] [--zoom <1-3>] [--no-auto-zoom] --out <file.icns>
          Write just the icon.
    """

    /// Returns an exit status if the arguments named a command, or nil to launch the GUI.
    static func runIfRequested(_ arguments: [String]) -> Int32? {
        guard arguments.count > 1 else { return nil }
        let options = Array(arguments.dropFirst(2))
        do {
            switch arguments[1] {
            case "build": try build(options)
            case "batch": return try batch(options)
            case "icon": try icon(options)
            case "help", "--help", "-h": print(usage)
            default: return nil // e.g. flags macOS passes when launching from Finder/Xcode
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private struct UsageError: LocalizedError {
        let message: String
        var errorDescription: String? { message + "\n\n" + CommandLineInterface.usage }
    }

    private static func value(_ flag: String, in options: [String]) -> String? {
        guard let index = options.firstIndex(of: flag), options.indices.contains(index + 1) else { return nil }
        return options[index + 1]
    }

    private static func iconSource(name: String, options: [String]) throws -> IconSource {
        guard let imagePath = value("--image", in: options) else {
            return .generated(name: name, symbol: value("--symbol", in: options))
        }
        let url = URL(fileURLWithPath: (imagePath as NSString).expandingTildeInPath)
        guard let image = NSImage(contentsOf: url) else {
            throw UsageError(message: "Couldn’t read an image from \(imagePath).")
        }
        // --zoom is on top of the automatic zoom that crops off any border, unless --no-auto-zoom.
        let extra = value("--zoom", in: options).flatMap(Double.init).map { CGFloat($0) } ?? 1
        let automatic = options.contains("--no-auto-zoom") ? 1 : IconRenderer.automaticZoom(for: image)
        let zoom = automatic * min(max(extra, IconSource.userZoomRange.lowerBound), IconSource.userZoomRange.upperBound)
        return .image(image, zoom: zoom)
    }

    private static func build(_ options: [String]) throws {
        guard let name = value("--name", in: options)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            throw UsageError(message: "--name is required.")
        }
        guard let rawURL = value("--url", in: options), let url = InputNormalizer.normalizeURL(rawURL) else {
            throw UsageError(message: "--url is required and must be a web address.")
        }
        // --name may include folders, e.g. "WebAppWrap/Photos".
        let location = AppLocation(name)
        guard !location.name.isEmpty else { throw UsageError(message: "--name needs an app name after any folders.") }
        let root = URL(fileURLWithPath: ((value("--out", in: options) ?? AppsFolder.current.path) as NSString).expandingTildeInPath)
        let titleBarColor: HexColor
        if let raw = value("--title-bar-color", in: options) {
            guard let parsed = HexColor(hex: raw) else { throw UsageError(message: "--title-bar-color must look like #1E1E1E.") }
            titleBarColor = parsed
        } else {
            // Like the app: default to the site's theme color.
            titleBarColor = waitFor { await ThemeColorFetcher.fetch(from: url) } ?? .defaultTitleBar
        }
        let spec = AppSpec(
            displayName: location.name,
            baseURL: url,
            icon: try iconSource(name: location.name, options: options),
            titleBarColor: titleBarColor
        )
        let app = try AppBuilder.build(spec, to: location.bundleURL(in: root))
        print(app.path)
    }

    /// Returns 1 if any app failed, after building all the others.
    private static func batch(_ options: [String]) throws -> Int32 {
        guard let path = options.first, !path.hasPrefix("--") else {
            throw UsageError(message: "batch needs the path of a JSON file.")
        }
        let file = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw UsageError(message: "Couldn’t read \(path).")
        }
        let entries = try BatchFile.parse(data, baseDirectory: file.deletingLastPathComponent())
        let root = URL(fileURLWithPath: ((value("--out", in: options) ?? AppsFolder.current.path) as NSString).expandingTildeInPath)

        let results = waitFor {
            await BatchBuilder.run(entries, into: root) { index, entry in
                print("[\(index + 1)/\(entries.count)] \(entry.location.name)…")
            }
        }
        var failures = 0
        for result in results {
            switch result.outcome {
            case let .success(app):
                print("✓ \(app.path)")
            case let .failure(error):
                failures += 1
                print("✗ \(result.entry.location.name): \(error.localizedDescription)")
            }
        }
        print("\(results.count - failures) of \(results.count) apps created.")
        return failures == 0 ? 0 : 1
    }

    /// Runs async work to completion from the synchronous command-line entry point.
    private static func waitFor<T>(_ work: @escaping () async -> T) -> T {
        let box = ResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await work()
            done.signal()
        }
        done.wait()
        return box.value!
    }

    private static func icon(_ options: [String]) throws {
        guard let out = value("--out", in: options) else { throw UsageError(message: "--out is required.") }
        let name = value("--name", in: options) ?? "App"
        let destination = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
        try IconRenderer.writeICNS(try iconSource(name: name, options: options), to: destination)
        print(destination.path)
    }
}

/// Hands a result from a detached task back to the thread waiting on the semaphore.
private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}
