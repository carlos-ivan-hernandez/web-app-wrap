import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebAppWrapKit

/// The inputs for one app while they're being edited: the one-off form, or an app in the list.
@MainActor
final class AppDraft: ObservableObject {
    @Published var displayName = ""
    @Published var urlString = "" {
        didSet { if urlString != oldValue { lookUpThemeColor() } }
    }

    enum TitleBarColorSource: Equatable {
        /// No site color known (no address yet, or the site doesn't declare one).
        case standard
        /// Fetching the site to find its theme color.
        case lookingUp
        /// Taken from the site's theme color.
        case site
        /// Picked by the user; site lookups no longer change it.
        case custom
    }

    @Published private(set) var titleBarColor = Color(nsColor: AppDraft.nsColor(.defaultTitleBar))
    @Published private(set) var titleBarColorSource = TitleBarColorSource.standard
    private var themeColorLookup: Task<Void, Never>?
    /// The user's zoom, on top of `baseZoom`. 1 = just enough to crop off the image's border.
    @Published var imageZoom: Double = 1
    @Published private(set) var baseZoom: CGFloat = 1
    @Published private(set) var customImage: NSImage?
    /// The file `customImage` came from. Saving copies it into WebAppWrap's icons folder.
    @Published private(set) var imageURL: URL?
    @Published private(set) var imageFileName = ""
    @Published private(set) var imageError: String?

    init() {}

    /// Starts from an app in the list. `iconURL` is where its stored icon is.
    init(settings: AppSettings, iconURL: URL?) {
        displayName = settings.name
        urlString = settings.url
        if let iconURL, loadImage(from: iconURL) {
            imageFileName = "Current icon"
        }
        imageZoom = settings.zoom
        if let hex = settings.titleBarColor.flatMap(HexColor.init(hex:)) {
            titleBarColor = Color(nsColor: Self.nsColor(hex))
            titleBarColorSource = .custom
        } else {
            lookUpThemeColor()
        }
    }

    /// The name field may include folders: "WebAppWrap/Photos" -> <apps folder>/WebAppWrap/Photos.app.
    var location: AppLocation { AppLocation(displayName) }
    var trimmedName: String { location.name }
    var destination: URL { location.bundleURL(in: AppsFolder.current) }
    var normalizedURL: URL? { InputNormalizer.normalizeURL(urlString) }
    var isValid: Bool { !trimmedName.isEmpty && normalizedURL != nil }

    var iconSource: IconSource {
        if let customImage { return .image(customImage, zoom: baseZoom * CGFloat(imageZoom)) }
        return trimmedName.isEmpty ? .generated(name: "", symbol: "globe") : .generated(name: trimmedName)
    }

    var previewImage: NSImage { IconRenderer.nsImage(iconSource, pixels: 320) }

    /// The color to save: nil while it follows the site's theme color.
    var chosenTitleBarColor: HexColor? { titleBarColorSource == .custom ? titleBarHex : nil }

    // MARK: - Icon image

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a square image for the app icon. 1024×1024 or larger looks best."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadImage(from: url)
    }

    @discardableResult
    func loadImage(from url: URL?) -> Bool {
        guard let url, let image = NSImage(contentsOf: url), image.isValid, image.size.width > 0 else {
            imageError = "That file isn’t an image macOS can read."
            return false
        }
        customImage = image
        imageURL = url
        imageFileName = url.lastPathComponent
        imageError = nil
        baseZoom = IconRenderer.automaticZoom(for: image)
        imageZoom = 1
        return true
    }

    func clearImage() {
        customImage = nil
        imageURL = nil
        imageFileName = ""
        imageError = nil
    }

    // MARK: - Title bar color

    func setTitleBarColor(_ color: Color) {
        themeColorLookup?.cancel()
        titleBarColor = color
        titleBarColorSource = .custom
    }

    /// Drops a custom pick and goes back to following the site's theme color.
    func useSiteThemeColor() {
        titleBarColorSource = .standard
        lookUpThemeColor()
    }

    /// Fetches the site's theme color shortly after the address stops changing.
    private func lookUpThemeColor() {
        themeColorLookup?.cancel()
        guard titleBarColorSource != .custom, let url = normalizedURL else { return }
        titleBarColorSource = .lookingUp
        themeColorLookup = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            let found = await ThemeColorFetcher.fetch(from: url)
            guard !Task.isCancelled, titleBarColorSource != .custom else { return }
            titleBarColor = Color(nsColor: Self.nsColor(found ?? .defaultTitleBar))
            titleBarColorSource = found == nil ? .standard : .site
        }
    }

    /// The picked title bar color as sRGB hex (the picker can hand back other color spaces).
    var titleBarHex: HexColor {
        guard let rgb = NSColor(titleBarColor).usingColorSpace(.sRGB) else { return .defaultTitleBar }
        return HexColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }

    static func nsColor(_ hex: HexColor) -> NSColor {
        NSColor(srgbRed: hex.red, green: hex.green, blue: hex.blue, alpha: 1)
    }
}
