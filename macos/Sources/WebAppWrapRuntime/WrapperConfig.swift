import Foundation
import WebAppWrapKit

/// What this wrapped app points at, read from its Info.plist.
struct WrapperConfig {
    let appName: String
    let baseURL: URL
    /// The color the app was built with, unless one was saved in WebAppWrap's list since
    /// (for example from the ⋮ menu's Title Bar Color).
    var titleBarColor: HexColor
    /// The app's ID in WebAppWrap's list, for its extension settings. nil for apps made from the command line.
    let appID: UUID?

    /// `--url <address>` overrides the Info.plist value, which is handy when running
    /// the bare runtime binary during development (`swift run WebAppWrapRuntime --url ...`).
    static func load(bundle: Bundle = .main, arguments: [String] = CommandLine.arguments) -> WrapperConfig? {
        let info = bundle.infoDictionary ?? [:]
        var rawURL = info[WrapperInfoKeys.baseURL] as? String
        if let flag = arguments.firstIndex(of: "--url"), arguments.indices.contains(flag + 1) {
            rawURL = arguments[flag + 1]
        }
        guard let rawURL, let url = InputNormalizer.normalizeURL(rawURL) else { return nil }

        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.host
            ?? ProcessInfo.processInfo.processName
        // Apps made before the color setting existed get the default.
        var color = (info[WrapperInfoKeys.titleBarColor] as? String).flatMap(HexColor.init(hex:)) ?? .defaultTitleBar
        let appID = (info[WrapperInfoKeys.appID] as? String).flatMap(UUID.init(uuidString:))
        if let saved = savedTitleBarColor(appID: appID) {
            color = saved
        }
        return WrapperConfig(appName: name, baseURL: url, titleBarColor: color, appID: appID)
    }

    /// The title bar color saved for this app in WebAppWrap's list, if any.
    static func savedTitleBarColor(appID: UUID?) -> HexColor? {
        guard let appID else { return nil }
        return AppRegistry.standard.settings(of: appID)?.titleBarColor.flatMap(HexColor.init(hex:))
    }
}
