import AppKit
import WebWrapKit

/// Scriptable entry points:
///   WebWrap build --name "Linear" --url linear.app [--image logo.png] [--style fill|fit|asIs] [--out ~/Applications]
///   WebWrap icon --name "Linear" [--symbol globe] [--image logo.png] [--style ...] --out AppIcon.icns
enum CommandLineInterface {
    static let usage = """
    Usage:
      WebWrap                      Open the app.
      WebWrap build --name <name> --url <address> [--image <file>] [--style fill|fit|asIs] [--out <folder>]
      WebWrap icon  --name <name> [--symbol <sf-symbol>] [--image <file>] [--style ...] --out <file.icns>
    """

    /// Returns an exit status if the arguments named a command, or nil to launch the GUI.
    static func runIfRequested(_ arguments: [String]) -> Int32? {
        guard arguments.count > 1 else { return nil }
        let options = Array(arguments.dropFirst(2))
        do {
            switch arguments[1] {
            case "build": try build(options)
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
        let style = value("--style", in: options).flatMap(ImageStyle.init(rawValue:))
            ?? (IconRenderer.hasTransparentEdges(image) ? .fit : .fill)
        return .image(image, style: style)
    }

    private static func build(_ options: [String]) throws {
        guard let name = value("--name", in: options)?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            throw UsageError(message: "--name is required.")
        }
        guard let rawURL = value("--url", in: options), let url = InputNormalizer.normalizeURL(rawURL) else {
            throw UsageError(message: "--url is required and must be a web address.")
        }
        let folder = URL(fileURLWithPath: ((value("--out", in: options) ?? "/Applications") as NSString).expandingTildeInPath)
        let spec = AppSpec(displayName: name, baseURL: url, icon: try iconSource(name: name, options: options))
        let app = try AppBuilder.build(spec, to: folder.appendingPathComponent(InputNormalizer.fileSafeName(name) + ".app"))
        print(app.path)
    }

    private static func icon(_ options: [String]) throws {
        guard let out = value("--out", in: options) else { throw UsageError(message: "--out is required.") }
        let name = value("--name", in: options) ?? "App"
        let destination = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
        try IconRenderer.writeICNS(try iconSource(name: name, options: options), to: destination)
        print(destination.path)
    }
}
