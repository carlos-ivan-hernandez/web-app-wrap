import AppKit
import CoreServices
import WebWrapKit

struct AppSpec {
    var displayName: String
    var baseURL: URL
    var icon: IconSource

    var bundleIdentifier: String { InputNormalizer.bundleIdentifier(for: displayName) }
}

enum BuildError: LocalizedError {
    case runtimeMissing
    case iconRenderingFailed
    case commandFailed(String, output: String)

    var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            "WebWrapRuntime is missing from this copy of WebWrap. Rebuild it with scripts/build.sh."
        case .iconRenderingFailed:
            "The icon couldn’t be drawn."
        case let .commandFailed(command, output):
            "\((command as NSString).lastPathComponent) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

/// Assembles a wrapped app: the prebuilt runtime binary, an Info.plist naming the
/// web address, and a generated icon, then ad-hoc signs it.
enum AppBuilder {
    /// The runtime ships inside WebWrap.app/Contents/Resources. When running from
    /// `swift run`, it sits next to the WebWrap executable in the build folder.
    static func runtimeBinaryURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "WebWrapRuntime", withExtension: nil) {
            return bundled
        }
        let sibling = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("WebWrapRuntime")
        if let sibling, FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }
        return nil
    }

    /// Builds the app at `destination` (a path ending in .app). An existing app there is moved to the Trash.
    @discardableResult
    static func build(_ spec: AppSpec, to destination: URL) throws -> URL {
        let fileManager = FileManager.default
        guard let runtime = runtimeBinaryURL() else { throw BuildError.runtimeMissing }

        let destination = destination.pathExtension == "app" ? destination : destination.appendingPathExtension("app")
        let executableName = InputNormalizer.fileSafeName(destination.deletingPathExtension().lastPathComponent)

        let staging = fileManager.temporaryDirectory.appendingPathComponent("WebWrap-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staging) }

        let app = staging.appendingPathComponent(destination.lastPathComponent)
        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        try fileManager.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

        let executable = macOS.appendingPathComponent(executableName)
        try fileManager.copyItem(at: runtime, to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        try IconRenderer.writeICNS(spec.icon, to: resources.appendingPathComponent("AppIcon.icns"))

        let plist = infoPlist(for: spec, executableName: executableName)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data("APPL????".utf8).write(to: contents.appendingPathComponent("PkgInfo"))

        // Extended attributes (e.g. quarantine copied from the runtime) make codesign refuse.
        try Shell.run("/usr/bin/xattr", ["-cr", app.path])
        try Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])

        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.moveItem(at: app, to: destination)

        // Tell Launch Services about the new bundle so Finder and the Dock pick up the icon.
        _ = LSRegisterURL(destination as CFURL, true)
        return destination
    }

    static func infoPlist(for spec: AppSpec, executableName: String) -> [String: Any] {
        let name = spec.displayName
        return [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": name,
            "CFBundleName": name,
            "CFBundleExecutable": executableName,
            "CFBundleIdentifier": spec.bundleIdentifier,
            "CFBundleIconFile": "AppIcon",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSApplicationCategoryType": "public.app-category.productivity",
            "LSMinimumSystemVersion": "13.0",
            "NSHighResolutionCapable": true,
            "NSPrincipalClass": "NSApplication",
            "NSSupportsAutomaticGraphicsSwitching": true,
            // Without these, a page asking for the camera or microphone crashes the app.
            "NSCameraUsageDescription": "\(name) uses the camera when the web page asks for it.",
            "NSMicrophoneUsageDescription": "\(name) uses the microphone when the web page asks for it.",
            // macOS 15+ asks before an app reaches devices on the local network (e.g. a home server).
            "NSLocalNetworkUsageDescription": "\(name) connects to servers on your local network when the web app uses them.",
            "NSAppTransportSecurity": ["NSAllowsArbitraryLoadsInWebContent": true],
            WrapperInfoKeys.baseURL: spec.baseURL.absoluteString,
        ]
    }
}

enum Shell {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BuildError.commandFailed(executable, output: output)
        }
        return output
    }
}
