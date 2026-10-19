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
    @Published var imageStyle: ImageStyle = .fill
    @Published private(set) var customImage: NSImage?
    @Published private(set) var imageFileName = ""
    @Published private(set) var status: Status = .idle

    var trimmedName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var normalizedURL: URL? { InputNormalizer.normalizeURL(urlString) }
    var bundleIdentifier: String { InputNormalizer.bundleIdentifier(for: trimmedName) }
    var canBuild: Bool { !trimmedName.isEmpty && normalizedURL != nil && status != .building }

    var iconSource: IconSource {
        if let customImage { return .image(customImage, style: imageStyle) }
        return trimmedName.isEmpty ? .generated(name: "", symbol: "globe") : .generated(name: trimmedName)
    }

    var previewImage: NSImage { IconRenderer.nsImage(iconSource, pixels: 320) }

    // MARK: - Icon image

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image for the app icon. Square images 1024×1024 or larger look best."
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
        imageStyle = IconRenderer.hasTransparentEdges(image) ? .fit : .fill
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

        let panel = NSSavePanel()
        panel.title = "Create App"
        panel.prompt = "Create"
        panel.nameFieldStringValue = InputNormalizer.fileSafeName(name) + ".app"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

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
