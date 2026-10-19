import Foundation
import WebAppWrapKit

/// What this wrapped app points at, read from its Info.plist.
struct WrapperConfig {
    let appName: String
    let baseURL: URL
    let titleBarColor: HexColor

    var policy: LinkPolicy { LinkPolicy(baseURL: baseURL) }

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
        let color = (info[WrapperInfoKeys.titleBarColor] as? String).flatMap(HexColor.init(hex:)) ?? .defaultTitleBar
        return WrapperConfig(appName: name, baseURL: url, titleBarColor: color)
    }
}
