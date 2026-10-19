import AppKit
import UniformTypeIdentifiers
import WebWrapKit

@MainActor
final class BuilderModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case building
        case finished(URL)
        case failed(String)
    }

    @Published var displayName = ""
    @Published var urlString = ""
    @Published var imageZoom: Double = 1
    @Published private(set) var customImage: NSImage?
    @Published private(set) var imageFileName = ""
    @Published private(set) var status: Status = .idle

    static let applicationsFolder = URL(fileURLWithPath: "/Applications", isDirectory: true)

    /// The name field may include folders: "WebWrap/Photos" -> /Applications/WebWrap/Photos.app.
    var location: AppLocation { AppLocation(displayName) }
    var trimmedName: String { location.name }
    var destination: URL { location.bundleURL(in: Self.applicationsFolder) }
    var normalizedURL: URL? { InputNormalizer.normalizeURL(urlString) }
    var bundleIdentifier: String { InputNormalizer.bundleIdentifier(for: trimmedName) }
    var canBuild: Bool { !trimmedName.isEmpty && normalizedURL != nil && status != .building }

    var iconSource: IconSource {
        if let customImage { return .image(customImage, zoom: CGFloat(imageZoom)) }
        return trimmedName.isEmpty ? .generated(name: "", symbol: "globe") : .generated(name: trimmedName)
    }

    var previewImage: NSImage { IconRenderer.nsImage(iconSource, pixels: 320) }

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
            status = .failed("That file isn’t an image macOS can read.")
            return false
        }
        customImage = image
        imageFileName = url.lastPathComponent
        imageZoom = Double(IconRenderer.automaticZoom(for: image))
        if case .failed = status { status = .idle }
        return true
    }

    func clearImage() {
        customImage = nil
        imageFileName = ""
    }

    // MARK: - Building

    func createApp() {
        guard canBuild, let url = normalizedURL else { return }
        let name = trimmedName

        let destination = self.destination

        if FileManager.default.fileExists(atPath: destination.path) {
            let alert = NSAlert()
            alert.messageText = "Replace \(destination.lastPathComponent)?"
            alert.informativeText = "An app already exists at \(destination.path). It will be moved to the Trash. Its sign-ins and settings are kept."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        let spec = AppSpec(displayName: name, baseURL: url, icon: iconSource)
        status = .building
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try AppBuilder.build(spec, to: destination) }
            }.value
            switch result {
            case let .success(app): status = .finished(app)
            case let .failure(error): status = .failed(error.localizedDescription)
            }
        }
    }

    func open(_ app: URL) {
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    func reveal(_ app: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([app])
    }
}
