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
    /// The user's zoom. For an SVG, 1 fits the whole SVG in the icon. For an older image, it's on
    /// top of `baseZoom`, and 1 is just enough to crop off the image's border.
    @Published var imageZoom: Double = 1
    @Published private(set) var baseZoom: CGFloat = 1
    @Published private(set) var customImage: NSImage?
    /// The file `customImage` came from. Saving copies it into WebAppWrap's icons folder.
    @Published private(set) var imageURL: URL?
    @Published private(set) var imageFileName = ""
    @Published private(set) var imageError: String?
    /// The fill behind an SVG icon.
    @Published var iconBackground = Color(nsColor: AppDraft.nsColor(.defaultIconBackground))

    init() {}

    /// Starts from an app in the list. `iconURL` is where its stored icon is.
    init(settings: AppSettings, iconURL: URL?) {
        displayName = settings.name
        urlString = settings.url
        // An app saved before SVG support may still have another kind of image; keep it working.
        if let iconURL, loadImage(from: iconURL, svgOnly: false) {
            imageFileName = "Current icon"
        }
        imageZoom = settings.zoom
        if let hex = settings.iconBackground.flatMap(HexColor.init(hex:)) {
            iconBackground = Color(nsColor: Self.nsColor(hex))
        }
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
        if let customImage {
            if imageIsSVG { return .svg(customImage, zoom: CGFloat(imageZoom), background: iconBackgroundHex) }
            return .image(customImage, zoom: baseZoom * CGFloat(imageZoom))
        }
        return trimmedName.isEmpty ? .generated(name: "", symbol: "globe") : .generated(name: trimmedName)
    }

    var previewImage: NSImage { IconRenderer.nsImage(iconSource, pixels: 320) }

    /// The color to save: nil while it follows the site's theme color.
    var chosenTitleBarColor: HexColor? { titleBarColorSource == .custom ? titleBarHex : nil }

    // MARK: - Icon image

    /// False only for an app saved before SVG support that still uses another kind of image.
    var imageIsSVG: Bool { imageURL.map(IconSource.isSVG) ?? false }

    var zoomRange: ClosedRange<Double> {
        let range = imageIsSVG ? IconSource.svgZoomRange : IconSource.userZoomRange
        return Double(range.lowerBound)...Double(range.upperBound)
    }

    /// The picked icon background as sRGB hex.
    var iconBackgroundHex: HexColor { Self.hex(iconBackground) ?? .defaultIconBackground }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.svg]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an SVG for the app icon. It’s drawn on the background color you pick."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadImage(from: url)
    }

    /// Loads an icon file. New icons must be SVGs; `svgOnly: false` also takes the other images
    /// apps saved before SVG support may have.
    @discardableResult
    func loadImage(from url: URL?, svgOnly: Bool = true) -> Bool {
        guard let url else { return false }
        let isSVG = IconSource.isSVG(url)
        if svgOnly, !isSVG {
            imageError = "Choose an SVG file."
            return false
        }
        guard let image = NSImage(contentsOf: url), image.isValid, image.size.width > 0, image.size.height > 0 else {
            imageError = isSVG ? "macOS couldn’t read that SVG." : "That file isn’t an image macOS can read."
            return false
        }
        customImage = image
        imageURL = url
        imageFileName = url.lastPathComponent
        imageError = nil
        baseZoom = isSVG ? 1 : IconRenderer.automaticZoom(for: image)
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
    var titleBarHex: HexColor { Self.hex(titleBarColor) ?? .defaultTitleBar }

    private static func hex(_ color: Color) -> HexColor? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return HexColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }

    static func nsColor(_ hex: HexColor) -> NSColor {
        NSColor(srgbRed: hex.red, green: hex.green, blue: hex.blue, alpha: 1)
    }
}
