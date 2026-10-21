import AppKit
import SwiftUI
import WebAppWrapKit

/// Extensions: browser extensions installed once and shared by every app WebAppWrap creates.
struct ExtensionsView: View {
    @ObservedObject var model: BuilderModel
    @State private var selection: String?
    @State private var choosingApps: ChooseAppsTarget?
    @State private var importing: ImportTarget?

    struct ChooseAppsTarget: Identifiable {
        let id: String
    }

    struct ImportTarget: Identifiable {
        let id = UUID()
        let found: [BrowserExtension]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = model.extensionsLoadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            List(selection: $selection) {
                ForEach(model.extensions) { installed in
                    ExtensionRow(model: model, installed: installed).tag(installed.id)
                }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first {
                    Button("Choose Apps…") { choosingApps = ChooseAppsTarget(id: id) }
                    Divider()
                    Button("Remove…") { confirmRemove(id) }
                }
            } primaryAction: { ids in
                if let id = ids.first { choosingApps = ChooseAppsTarget(id: id) }
            }
            .onDeleteCommand { if let selection { confirmRemove(selection) } }
            .frame(height: 300)
            .overlay {
                if model.extensions.isEmpty && model.extensionsLoadError == nil {
                    Text("No extensions yet. Click + to add one from Chrome or from a file.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Menu {
                    Button("Import from Chrome or Another Browser…") { openImport() }
                    Button("Add from File or Folder…") { model.chooseExtensionToInstall() }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add an extension")
                Button { if let selection { confirmRemove(selection) } } label: { Image(systemName: "minus") }
                    .help("Remove the selected extension")
                    .disabled(selection == nil)
                Button("Choose Apps…") { if let selection { choosingApps = ChooseAppsTarget(id: selection) } }
                    .disabled(selection == nil)
                Spacer()
            }
            .controlSize(.small)
            .disabled(model.extensionsLoadError != nil)

            Text("""
            Extensions work in apps on macOS 15.4 or later. A running app picks up changes here \
            the next time you switch to it. You can also turn extensions on and off from an app’s \
            Extensions menu.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 10) {
                HelpButton()
                Spacer()
            }
            .frame(minHeight: 28)
        }
        .padding(24)
        .onAppear { model.reloadExtensions() }
        .sheet(item: $choosingApps) { target in
            ExtensionAppsSheet(model: model, extensionID: target.id)
        }
        .sheet(item: $importing) { target in
            BrowserImportSheet(model: model, found: target.found)
        }
    }

    private func openImport() {
        let found = model.browserExtensions()
        guard !found.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No browser extensions found"
            alert.informativeText = "WebAppWrap looks in Chrome, Chromium, Brave, Edge, Helium, Vivaldi, Arc, Dia, Comet, Opera, Yandex and Thorium, including their beta and nightly versions. To install another extension, use Add from File or Folder."
            alert.runModal()
            return
        }
        importing = ImportTarget(found: found)
    }

    private func confirmRemove(_ id: String) {
        guard let installed = model.extensions.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(installed.name)?"
        alert.informativeText = "It’s removed from every app the next time you switch to it. Its settings in each app are kept, in case you install it again."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.uninstallExtension(id)
        if selection == id { selection = nil }
    }
}

private struct ExtensionRow: View {
    @ObservedObject var model: BuilderModel
    let installed: InstalledExtension
    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "puzzlepiece.extension").resizable().scaledToFit().foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(installed.name).lineLimit(1)
                    Text(installed.version).font(.caption).foregroundStyle(.secondary)
                }
                Text(model.availabilitySummary(installed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            if let source = installed.source {
                Text(source).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .task(id: installed.folder) { icon = model.extensionIcon(installed) }
    }
}

/// Which apps an extension is on for: a default, and a switch for each app in My Apps.
private struct ExtensionAppsSheet: View {
    @ObservedObject var model: BuilderModel
    let extensionID: String
    @Environment(\.dismiss) private var dismiss

    private var installed: InstalledExtension? {
        model.extensions.first { $0.id == extensionID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let installed {
                Text(installed.name).font(.title2.weight(.semibold))
                Toggle("On for apps without their own setting", isOn: Binding(
                    get: { installed.enabledByDefault },
                    set: { model.setExtension(extensionID, enabledByDefault: $0) }
                ))
                Text("This includes new apps and apps made from the command line.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.records.isEmpty {
                    Text("Apps you add in My Apps appear here.")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(model.records) { record in
                            Toggle(isOn: Binding(
                                get: { installed.isEnabled(forApp: record.id) },
                                set: { model.setExtension(extensionID, enabled: $0, forApp: record.id) }
                            )) {
                                HStack {
                                    Text(record.settings.name)
                                    if installed.apps[record.id.uuidString.lowercased()] != nil {
                                        Text("Own setting").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 260)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

/// Extensions found in Chrome and other Chromium browsers, to pick from.
private struct BrowserImportSheet: View {
    @ObservedObject var model: BuilderModel
    let found: [BrowserExtension]
    @State private var chosen = Set<String>()
    /// Browsers turned off in the Browsers menu, one per line. Remembered between imports.
    @AppStorage("hiddenImportBrowsers") private var hiddenBrowsersText = ""
    @Environment(\.dismiss) private var dismiss

    /// Browsers with extensions to import, in the order WebAppWrap looks in them.
    private var browsers: [String] {
        let present = Set(found.map(\.browser))
        return BrowserExtension.browsers.map(\.name).filter(present.contains)
    }

    private var hiddenBrowsers: Set<String> {
        Set(hiddenBrowsersText.split(separator: "\n").map(String.init))
    }

    private var shown: [BrowserExtension] {
        let hidden = hiddenBrowsers
        return found.filter { !hidden.contains($0.browser) }
    }

    private func setBrowser(_ browser: String, shown isShown: Bool) {
        var hidden = hiddenBrowsers
        if isShown { hidden.remove(browser) } else { hidden.insert(browser) }
        hiddenBrowsersText = hidden.sorted().joined(separator: "\n")
        if !isShown { chosen = chosen.filter { !$0.hasPrefix(browser + "/") } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Import Extensions").font(.title2.weight(.semibold))
                Spacer()
                browserMenu
            }
            Text("Extensions installed in your browsers. Each app gets its own copy of an extension’s settings, so settings from your browser don’t carry over.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List {
                ForEach(shown) { item in
                    Toggle(isOn: Binding(
                        get: { chosen.contains(item.id) },
                        set: { if $0 { chosen.insert(item.id) } else { chosen.remove(item.id) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.manifest.name)
                                Text(item.manifest.version).font(.caption).foregroundStyle(.secondary)
                                if model.extensions.contains(where: { $0.id == InputNormalizer.slug(item.manifest.name) }) {
                                    Text("Installed").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text("\(item.browser) · \(item.profile)").font(.caption).foregroundStyle(.secondary)
                            if !item.manifest.unsupportedPermissions.isEmpty {
                                Text("May not fully work: it \(item.manifest.unsupportedPermissions.joined(separator: ", ")).")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .frame(height: 320)
            .overlay {
                if shown.isEmpty {
                    Text("All browsers are turned off. Choose some from the Browsers menu.")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(chosen.count > 1 ? "Import \(chosen.count)" : "Import") {
                    let items = shown.filter { chosen.contains($0.id) }
                    dismiss()
                    // After the sheet closes, so the confirmation isn't stacked on top of it.
                    DispatchQueue.main.async { model.importBrowserExtensions(items) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    /// Turns each browser's extensions on or off in the list.
    private var browserMenu: some View {
        let hidden = hiddenBrowsers
        let label = hidden.isDisjoint(with: browsers)
            ? "All Browsers"
            : "\(browsers.filter { !hidden.contains($0) }.count) of \(browsers.count) Browsers"
        return Menu(label) {
            ForEach(browsers, id: \.self) { browser in
                Toggle("\(browser) (\(found.filter { $0.browser == browser }.count))", isOn: Binding(
                    get: { !hiddenBrowsers.contains(browser) },
                    set: { setBrowser(browser, shown: $0) }
                ))
            }
            Divider()
            Button("Show All") { browsers.forEach { setBrowser($0, shown: true) } }
        }
        .fixedSize()
        .help("Choose which browsers’ extensions are listed")
    }
}
