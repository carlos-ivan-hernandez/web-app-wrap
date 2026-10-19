import SwiftUI

struct ContentView: View {
    @ObservedObject var model: BuilderModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 28) {
                iconColumn
                fieldsColumn
            }
            Divider()
            footer
        }
        .padding(24)
        .frame(width: 620)
    }

    // MARK: - Icon

    private var iconColumn: some View {
        VStack(spacing: 10) {
            Image(nsImage: model.previewImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 148, height: 148)
                .padding(8)
                .dropDestination(for: URL.self) { urls, _ in
                    model.loadImage(from: urls.first)
                }
                .help("Drop an image here")

            HStack(spacing: 6) {
                Button("Choose Image…") { model.chooseImage() }
                if model.customImage != nil {
                    Button("Use Default") { model.clearImage() }
                }
            }
            .controlSize(.small)

            if model.customImage != nil {
                HStack(spacing: 6) {
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                    Slider(
                        value: $model.imageZoom,
                        in: Double(IconSource.userZoomRange.lowerBound)...Double(IconSource.userZoomRange.upperBound)
                    )
                    .controlSize(.small)
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                }
                .help("Zoom in on the image")
            }

            Text(model.customImage == nil ? "Default icon. Drop an image to use your own." : model.imageFileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(width: 176)
    }

    // MARK: - Fields

    private var fieldsColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            labeled("App name") {
                TextField("e.g. Linear, or Web App Wrap/Linear", text: $model.displayName)
                    .textFieldStyle(.roundedBorder)
                if model.trimmedName.isEmpty {
                    caption("Shown in the Dock, menu bar and Finder. Add folders with “/”.")
                } else {
                    caption("Saves to \(model.destination.path)")
                }
            }

            labeled("Web address") {
                TextField("e.g. linear.app", text: $model.urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.createApp() }
                if model.urlString.trimmingCharacters(in: .whitespaces).isEmpty {
                    caption("New tabs open here. Links to other sites open in your browser.")
                } else if let url = model.normalizedURL {
                    caption("Opens \(url.absoluteString)")
                } else {
                    caption("Enter a web address like example.com or https://example.com/app.", color: .red)
                }
            }

            labeled("Title bar color") {
                HStack(spacing: 8) {
                    ColorPicker(
                        "Title bar color",
                        selection: Binding(get: { model.titleBarColor }, set: { model.setTitleBarColor($0) }),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    caption(model.titleBarHex.hexString)
                        .textSelection(.enabled)
                    switch model.titleBarColorSource {
                    case .lookingUp:
                        ProgressView().controlSize(.small)
                        caption("Checking the site’s theme color…")
                    case .site:
                        caption("From the site’s theme color")
                    case .standard:
                        caption(model.normalizedURL == nil ? "Default" : "Default (the site has no theme color)")
                    case .custom:
                        caption("Custom")
                        Button("Use Site Color") { model.useSiteThemeColor() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                caption("Background of the bar holding the window buttons and tabs.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button { openWindow(id: HelpView.windowID) } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Web App Wrap Help")
            statusView
            Spacer()
            Button("Create from JSON…") { model.createAppsFromJSON() }
                .disabled(model.status.isBusy)
                .help("Create several apps from a JSON file (⇧⌘O)")
            Button("Create App") { model.createApp() }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canBuild)
        }
        .frame(minHeight: 28)
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .building:
            ProgressView().controlSize(.small)
            Text("Building…").foregroundStyle(.secondary)
        case let .finished(app):
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Created \(app.lastPathComponent)").lineLimit(1).truncationMode(.middle)
            Button("Open") { model.open(app) }
            Button("Show in Finder") { model.reveal(app) }
        case let .failed(message):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
        case let .buildingBatch(current, total, name):
            ProgressView().controlSize(.small)
            Text("Building \(current) of \(total): \(name)…")
                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        case let .batchFinished(created, failed):
            Image(systemName: failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(failed == 0 ? .green : .orange)
            Text(failed == 0 ? "Created \(created.count) apps" : "Created \(created.count), \(failed) failed")
                .lineLimit(1)
            if !created.isEmpty {
                Button("Show in Finder") { model.reveal(created) }
            }
        }
    }

    // MARK: - Helpers

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            content()
        }
    }

    private func caption(_ text: String, color: Color = .secondary) -> Text {
        Text(text).font(.caption).foregroundColor(color)
    }
}
