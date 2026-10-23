import SwiftUI
import WebAppWrapKit

/// The icon, name, address and title bar color fields of the sheet that adds or edits an app.
struct AppForm: View {
    @ObservedObject var draft: AppDraft
    var onSubmit: () -> Void = {}
    /// Read so the "Saves to" path updates when the apps folder changes.
    @AppStorage(AppsFolder.defaultsKey) private var appsFolderPath = ""

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            iconColumn
            fieldsColumn
        }
    }

    // MARK: - Icon

    private var iconColumn: some View {
        VStack(spacing: 10) {
            Image(nsImage: draft.previewImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 148, height: 148)
                .padding(8)
                .dropDestination(for: URL.self) { urls, _ in
                    draft.loadImage(from: urls.first)
                }
                .help("Drop an SVG here")

            HStack(spacing: 6) {
                Button("Choose SVG…") { draft.chooseImage() }
                if draft.customImage != nil {
                    Button("Use Default") { draft.clearImage() }
                }
            }
            .controlSize(.small)

            if draft.customImage != nil {
                HStack(spacing: 6) {
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                    Slider(value: $draft.imageZoom, in: draft.zoomRange)
                        .controlSize(.small)
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                }
                .help(draft.imageIsSVG ? "Zoom the SVG out or in" : "Zoom in on the image")
            }

            if draft.customImage != nil, draft.imageIsSVG {
                HStack(spacing: 6) {
                    ColorPicker("Background", selection: $draft.iconBackground, supportsOpacity: false)
                    Text(draft.iconBackgroundHex.hexString)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.caption)
                .controlSize(.small)
                .help("The color behind the SVG")

                HStack(spacing: 6) {
                    Picker("SVG", selection: $draft.usesSVGColor) {
                        Text("Original Colors").tag(false)
                        Text("One Color").tag(true)
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    if draft.usesSVGColor {
                        ColorPicker("SVG color", selection: $draft.svgColor, supportsOpacity: false)
                            .labelsHidden()
                        Text(draft.svgColorHex?.hexString ?? "")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .font(.caption)
                .controlSize(.small)
                .help("Keep the SVG’s own colors, or fill it with one color")
            }

            Group {
                if let error = draft.imageError {
                    Text(error).foregroundColor(.red)
                } else {
                    Text(draft.customImage == nil ? "Default icon. Drop an SVG to use your own." : draft.imageFileName)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
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
                TextField("e.g. Linear, or WebAppWrap/Linear", text: $draft.displayName)
                    .textFieldStyle(.roundedBorder)
                if draft.trimmedName.isEmpty {
                    caption("Shown in the Dock, menu bar and Finder. Add folders with “/”.")
                } else {
                    caption("Saves to \(AppsFolder.displayPath(draft.destination))")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(draft.destination.path)
                }
            }

            labeled("Web address") {
                TextField("e.g. linear.app", text: $draft.urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onSubmit)
                if draft.urlString.trimmingCharacters(in: .whitespaces).isEmpty {
                    caption("New tabs open here. Links to other sites open in your browser.")
                } else if let url = draft.normalizedURL {
                    caption("Opens \(url.absoluteString)")
                } else {
                    caption("Enter a web address like example.com or https://example.com/app.", color: .red)
                }
            }

            labeled("Title bar color") {
                HStack(spacing: 8) {
                    ColorPicker(
                        "Title bar color",
                        selection: Binding(get: { draft.titleBarColor }, set: { draft.setTitleBarColor($0) }),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    caption(draft.titleBarHex.hexString)
                        .textSelection(.enabled)
                    switch draft.titleBarColorSource {
                    case .lookingUp:
                        ProgressView().controlSize(.small)
                        caption("Checking the site’s theme color…")
                    case .site:
                        caption("From the site’s theme color")
                    case .standard:
                        caption(draft.normalizedURL == nil ? "Default" : "Default (the site has no theme color)")
                    case .custom:
                        caption("Custom")
                        Button("Use Site Color") { draft.useSiteThemeColor() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                caption("Background of the bar holding the window buttons and tabs.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
