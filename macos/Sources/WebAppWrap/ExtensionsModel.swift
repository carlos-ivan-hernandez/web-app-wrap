import AppKit
import UniformTypeIdentifiers
import WebAppWrapKit

/// Installing browser extensions and choosing which apps use them. The apps themselves load
/// them (see WebAppWrapRuntime/ExtensionHost.swift); nothing here needs a rebuild.
extension BuilderModel {
    func reloadExtensions() {
        do {
            extensions = try extensionStore.load()
            extensionsLoadError = nil
        } catch {
            extensions = []
            extensionsLoadError = "\(extensionStore.listFile.path) couldn’t be read: \(error.localizedDescription)"
        }
    }

    // MARK: - Installing

    /// Asks for an unpacked extension folder, a .zip or a .crx, then installs it.
    func chooseExtensionToInstall() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, .zip] + [UTType(filenameExtension: "crx")].compactMap { $0 }
        panel.message = "Choose an unpacked extension folder (with a manifest.json), or a .zip or .crx file."
        panel.prompt = "Install"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        installExtension(from: url)
    }

    func installExtension(from url: URL) {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appendingPathComponent("WebAppWrapExtension-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: work) }
        do {
            let root = try unpackedExtension(at: url, workFolder: work)
            let manifest = try ExtensionManifest.read(from: root)
            guard confirmInstall([manifest]) else { return }
            try extensionStore.install(from: root, manifest: manifest, sourceName: url.lastPathComponent)
            reloadExtensions()
        } catch {
            showExtensionError("\(url.lastPathComponent) couldn’t be installed", error)
        }
    }

    /// Installs extensions found in Chrome and other Chromium browsers. Confirms once for all of them.
    func importBrowserExtensions(_ found: [BrowserExtension]) {
        guard !found.isEmpty, confirmInstall(found.map(\.manifest)) else { return }
        var failures: [String] = []
        for item in found {
            do {
                try extensionStore.install(from: item.folder, manifest: item.manifest, sourceName: item.browser)
            } catch {
                failures.append("\(item.manifest.name): \(error.localizedDescription)")
            }
        }
        reloadExtensions()
        if !failures.isEmpty {
            showExtensionError("Some extensions couldn’t be installed", SaveError(message: failures.joined(separator: "\n")))
        }
    }

    func browserExtensions() -> [BrowserExtension] {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return BrowserExtension.find(applicationSupport: support)
    }

    /// The folder holding manifest.json: the chosen folder, or a .zip or .crx unpacked into `workFolder`.
    private func unpackedExtension(at url: URL, workFolder: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let folder: URL
        if isDirectory.boolValue {
            folder = url
        } else {
            try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
            let zip = workFolder.appendingPathComponent("extension.zip")
            try CRXFile.zipData(from: Data(contentsOf: url)).write(to: zip)
            folder = workFolder.appendingPathComponent("unpacked", isDirectory: true)
            try Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path])
        }
        guard let root = ExtensionManifest.root(in: folder) else {
            throw SaveError(message: "There’s no manifest.json in \(url.lastPathComponent), so it isn’t an extension.")
        }
        return root
    }

    /// Lists what the extensions can do, and anything WebKit doesn't support.
    private func confirmInstall(_ manifests: [ExtensionManifest]) -> Bool {
        let alert = NSAlert()
        alert.messageText = manifests.count == 1
            ? "Install \(manifests[0].name) \(manifests[0].version)?"
            : "Install \(manifests.count) extensions?"
        var details: [String] = []
        for manifest in manifests {
            var lines: [String] = []
            if manifests.count > 1 { lines.append("\(manifest.name) \(manifest.version)") }
            if let current = extensions.first(where: { $0.id == InputNormalizer.slug(manifest.name) }) {
                lines.append("Replaces version \(current.version). Its app settings are kept.")
            }
            lines += manifest.accessSummary.map { "• \($0)" }
            if !manifest.unsupportedPermissions.isEmpty {
                lines.append("May not fully work: it \(manifest.unsupportedPermissions.joined(separator: ", ")).")
            }
            details.append(lines.joined(separator: "\n"))
        }
        details.append("""
        Installing grants these permissions in every app the extension is on for. \
        It’s on for all apps until you change that.
        """)
        alert.informativeText = details.joined(separator: "\n\n")
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Choosing apps

    func setExtension(_ id: String, enabledByDefault enabled: Bool) {
        changeExtension(id) { $0.setEnabledByDefault(enabled) }
    }

    func setExtension(_ id: String, enabled: Bool, forApp appID: UUID) {
        changeExtension(id) { $0.setEnabled(enabled, forApp: appID) }
    }

    /// Saves the switches from an app's edit sheet: extension ID -> on or off for that app.
    func setExtensions(_ states: [String: Bool], forApp appID: UUID) {
        reloadExtensions()
        for (id, enabled) in states {
            guard let installed = extensions.first(where: { $0.id == id }), installed.isEnabled(forApp: appID) != enabled else { continue }
            setExtension(id, enabled: enabled, forApp: appID)
        }
    }

    func uninstallExtension(_ id: String) {
        do {
            try extensionStore.uninstall(id)
        } catch {
            showExtensionError("The extension couldn’t be removed", error)
        }
        reloadExtensions()
    }

    /// Which apps an extension is on for, in words.
    func availabilitySummary(_ installed: InstalledExtension) -> String {
        let exceptions = records.filter { installed.isEnabled(forApp: $0.id) != installed.enabledByDefault }
        let names = exceptions.prefix(3).map(\.settings.location.name).joined(separator: ", ")
        let more = exceptions.count > 3 ? " and \(exceptions.count - 3) more" : ""
        switch (installed.enabledByDefault, exceptions.isEmpty) {
        case (true, true): return "On for all apps"
        case (true, false): return "On for all apps except \(names)\(more)"
        case (false, true): return "Off for all apps"
        case (false, false): return "Off by default · on for \(names)\(more)"
        }
    }

    func extensionIcon(_ installed: InstalledExtension) -> NSImage? {
        let folder = extensionStore.resourceURL(for: installed)
        guard let path = (try? ExtensionManifest.read(from: folder))?.iconPath else { return nil }
        return NSImage(contentsOf: folder.appendingPathComponent(path))
    }

    private func changeExtension(_ id: String, _ change: (inout InstalledExtension) -> Void) {
        do {
            extensions = try extensionStore.update(id, change)
        } catch {
            showExtensionError("The extension’s settings couldn’t be saved", error)
        }
    }

    private func showExtensionError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
