import SwiftUI

struct ContentView: View {
    @StateObject private var model = BuilderModel()
    @State private var isDropTargeted = false

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
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
                }
                .dropDestination(for: URL.self) { urls, _ in
                    model.loadImage(from: urls.first)
                } isTargeted: {
                    isDropTargeted = $0
                }
                .help("Drop an image here")

            HStack(spacing: 6) {
                Button("Choose Image…") { model.chooseImage() }
                if model.customImage != nil {
                    Button("Use Default") { model.clearImage() }
                }
            }
            .controlSize(.small)

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
                TextField("e.g. Linear", text: $model.displayName)
                    .textFieldStyle(.roundedBorder)
                caption(model.trimmedName.isEmpty ? "Shown in the Dock, menu bar and Finder." : "Bundle ID: \(model.bundleIdentifier)")
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

            if model.customImage != nil {
                labeled("Icon style") {
                    Picker("Icon style", selection: $model.imageStyle) {
                        ForEach(ImageStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            statusView
            Spacer()
            Button("Create App…") { model.createApp() }
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
