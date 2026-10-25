import AppKit
import CoreServices
import SwiftUI
import WebAppWrapKit

@MainActor
final class BuilderModel: ObservableObject {
    enum Status: Equatable {
        case idle
        /// Building app `current` (1-based) of `total` from the list.
        case buildingList(current: Int, total: Int, name: String)
        case listFinished(created: [URL], failed: Int, skipped: Int)

        var isBusy: Bool {
            switch self {
            case .buildingList: true
            default: false
            }
        }
    }

    enum Mode: String {
        case list
        case extensions
    }

    @Published var mode = Mode.list
    /// Where apps are saved. Change it with `chooseAppsFolder()`.
    @Published private(set) var appsFolder = AppsFolder.current
    @Published private(set) var status: Status = .idle

    let registry = AppRegistry.standard
    /// Every app WebAppWrap has created, plus any added to the list and not built yet.
    @Published private(set) var records: [AppRecord] = []
    /// Set if apps.json couldn't be read. The list isn't saved while this is set, so a
    /// damaged file is never overwritten.
    @Published private(set) var loadError: String?

    let extensionStore = ExtensionStore.standard
    /// Browser extensions installed once and shared by every app (see ExtensionsModel.swift).
    @Published var extensions: [InstalledExtension] = []
    @Published var extensionsLoadError: String?

    init() {
        do {
            records = try registry.load()
        } catch {
            loadError = "\(registry.listFile.path) couldn’t be read: \(error.localizedDescription)"
        }
        // Extensions installed by an older WebAppWrap get the current compatibility script.
        extensionStore.updateCompatibility()
        reloadExtensions()
    }

    // MARK: - The list

    /// Reads apps.json again. Apps change their own settings there (e.g. the title bar color
    /// from their ⋮ menu), and the list is always saved whole, so it must be current first.
    func reloadRecords() {
        guard !status.isBusy, FileManager.default.fileExists(atPath: registry.listFile.path) else { return }
        do {
            let loaded = try registry.load()
            if loaded != records { records = loaded }
            loadError = nil
        } catch {
            loadError = "\(registry.listFile.path) couldn’t be read: \(error.localizedDescription)"
        }
    }

    func findRecord(_ id: UUID) -> AppRecord? {
        records.first { $0.id == id }
    }

    func appURL(for record: AppRecord) -> URL {
        record.settings.location.bundleURL(in: appsFolder)
    }

    func buildReason(for record: AppRecord) -> AppRecord.BuildReason? {
        record.buildReason(
            currentVersion: GeneratorVersion.commit,
            appExists: FileManager.default.fileExists(atPath: appURL(for: record).path)
        )
    }

    func iconURL(for record: AppRecord) -> URL? {
        record.settings.icon.map(registry.iconURL)
    }

    /// A message saying why `draft` can't be saved as app `id`, or nil if it can.
    func problem(saving draft: AppDraft, as id: UUID) -> String? {
        if loadError != nil { return "Your list of apps couldn’t be read, so it can’t be changed." }
        guard draft.isValid else { return "Enter an app name and a web address." }
        let key = draft.location.key
        if records.contains(where: { $0.id != id && $0.settings.location.key == key }) {
            return "Another app in the list already uses \(draft.destination.path)."
        }
        return nil
    }

    /// Saves an added or edited app as `id` (a new ID adds it). Building happens separately.
    func save(_ draft: AppDraft, as id: UUID) throws {
        if let problem = problem(saving: draft, as: id) {
            throw SaveError(message: problem)
        }
        let existing = findRecord(id)
        var record = existing ?? AppRecord(id: id, settings: AppSettings(name: "", url: ""))
        record.settings = try settings(from: draft, id: record.id, replacing: existing?.settings)
        try store(record)
    }

    /// Takes the app off the list. The app itself stays installed; its icon moves to previous-icons.
    func remove(_ id: UUID) throws {
        guard loadError == nil, let record = findRecord(id) else { return }
        if let icon = record.settings.icon {
            try registry.retireIcon(icon, appName: record.settings.name)
        }
        var updated = records
        updated.removeAll { $0.id == id }
        try registry.save(updated)
        records = updated
    }

    struct SaveError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The draft as saved settings. Copies a new icon into the icons folder and moves the one
    /// it replaces into previous-icons.
    private func settings(from draft: AppDraft, id: UUID, replacing current: AppSettings?) throws -> AppSettings {
        guard let url = draft.normalizedURL else { throw SaveError(message: "Enter a web address.") }
        var icon: String?
        if let imageURL = draft.imageURL {
            icon = try registry.importIcon(from: imageURL, for: id, replacing: current?.icon)
        }
        if let current, let oldIcon = current.icon, oldIcon != icon {
            try registry.retireIcon(oldIcon, appName: current.name)
        }
        let location = draft.location
        return AppSettings(
            name: (location.folders + [location.name]).joined(separator: "/"),
            url: url.absoluteString,
            icon: icon,
            zoom: icon == nil ? 1 : draft.imageZoom,
            iconBackground: icon != nil && draft.imageIsSVG ? draft.iconBackgroundHex.hexString : nil,
            iconColor: icon != nil && draft.imageIsSVG ? draft.svgColorHex?.hexString : nil,
            titleBarColor: draft.chosenTitleBarColor?.hexString
        )
    }

    /// Adds or replaces `record` and writes the list.
    private func store(_ record: AppRecord) throws {
        guard loadError == nil else { throw SaveError(message: "Your list of apps couldn’t be read, so it can’t be changed.") }
        var updated = records
        if let index = updated.firstIndex(where: { $0.id == record.id }) {
            updated[index] = record
        } else {
            updated.append(record)
        }
        try registry.save(updated)
        records = updated
    }

    // MARK: - Building the list

    /// What Build Apps is about to do, shown on its own page before anything is built.
    struct BuildPlan {
        let targets: [AppRecord]
        /// Up-to-date apps left out. Always 0 when building chosen apps.
        let skipped: Int
        /// Why each target is built, as of when the page opened. Missing for up-to-date apps
        /// built by choice.
        let reasons: [UUID: AppRecord.BuildReason]
        /// Targets already in the apps folder, which are moved to the Trash first.
        let replacing: Set<UUID>
        /// How each target went, filled in as the build runs.
        var outcomes: [UUID: Outcome] = [:]
        var isFinished = false

        enum Outcome {
            case built(URL)
            case failed(String)
        }
    }

    /// The Build Apps page, while it's open.
    @Published var buildPlan: BuildPlan?

    /// Opens the Build Apps page for the apps in the list that changed, were built by another
    /// version of WebAppWrap, or are missing. Up-to-date apps are skipped. With `only`, it's
    /// just those apps, even if they're up to date. Nothing is built until `startBuild()`.
    func reviewBuild(only ids: Set<UUID>? = nil) {
        guard !status.isBusy, loadError == nil else { return }
        let candidates = ids.map { ids in records.filter { ids.contains($0.id) } } ?? records
        let targets = ids == nil ? candidates.filter { buildReason(for: $0) != nil } : candidates
        guard !targets.isEmpty else { return }
        var reasons: [UUID: AppRecord.BuildReason] = [:]
        for record in targets { reasons[record.id] = buildReason(for: record) }
        let replacing = Set(targets.filter { FileManager.default.fileExists(atPath: appURL(for: $0).path) }.map(\.id))
        buildPlan = BuildPlan(
            targets: targets, skipped: ids == nil ? records.count - targets.count : 0,
            reasons: reasons, replacing: replacing
        )
    }

    /// Leaves the Build Apps page. Not while it's building.
    func closeBuild() {
        guard !status.isBusy else { return }
        buildPlan = nil
    }

    /// Builds the apps on the Build Apps page.
    func startBuild() {
        guard !status.isBusy, loadError == nil, let plan = buildPlan, !plan.isFinished else { return }
        let targets = plan.targets
        let iconsFolder = registry.iconsFolder
        let jobs = targets.compactMap { record in record.batchEntry(iconsFolder: iconsFolder).map { (record, $0) } }
        let root = appsFolder
        let version = GeneratorVersion.commit
        status = .buildingList(current: 1, total: jobs.count, name: jobs.first?.1.location.name ?? "")
        Task {
            let results = await Task.detached(priority: .userInitiated) {
                await BatchBuilder.run(jobs.map { $0.1 }, appIDs: jobs.map { $0.0.id }, into: root) { index, entry in
                    await MainActor.run {
                        self.status = .buildingList(current: index + 1, total: jobs.count, name: entry.location.name)
                    }
                }
            }.value

            var outcomes: [UUID: BuildPlan.Outcome] = [:]
            var created: [URL] = []
            var failed = 0
            var updated = records
            for ((record, _), result) in zip(jobs, results) {
                switch result.outcome {
                case let .success(app):
                    created.append(app)
                    outcomes[record.id] = .built(app)
                    if let index = updated.firstIndex(where: { $0.id == record.id }) {
                        updated[index].lastBuild = BuildStamp(version: version, date: Date(), settings: record.settings)
                    }
                case let .failure(error):
                    failed += 1
                    outcomes[record.id] = .failed(error.localizedDescription)
                }
            }
            // An entry whose web address no longer parses never reaches the builder.
            for record in targets where !jobs.contains(where: { $0.0.id == record.id }) {
                failed += 1
                outcomes[record.id] = .failed("“\(record.settings.url)” isn’t a web address.")
            }
            var saveError: String?
            do {
                try registry.save(updated)
                records = updated
            } catch {
                failed += 1
                saveError = "The list couldn’t be saved: \(error.localizedDescription)"
            }
            status = .listFinished(created: created, failed: failed, skipped: plan.skipped)
            buildPlan?.outcomes = outcomes
            buildPlan?.isFinished = true

            if let saveError {
                let report = NSAlert()
                report.alertStyle = .warning
                report.messageText = "Your list of apps couldn’t be saved"
                report.informativeText = saveError
                report.runModal()
            }
        }
    }

    // MARK: - Apps folder

    /// Asks for a new folder to save apps in.
    func chooseAppsFolder() {
        guard !status.isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = appsFolder
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder WebAppWrap saves your apps in."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setAppsFolder(url)
    }

    /// Saves apps in `folder` from now on. Apps in My Apps that are already built can move
    /// along with it; otherwise Build Apps builds new copies there.
    func setAppsFolder(_ folder: URL) {
        let old = appsFolder
        let new = folder.standardizedFileURL
        guard !status.isBusy, new.path != old.standardizedFileURL.path else { return }

        let fileManager = FileManager.default
        let movable = records.filter { record in
            fileManager.fileExists(atPath: record.settings.location.bundleURL(in: old).path)
                && !fileManager.fileExists(atPath: record.settings.location.bundleURL(in: new).path)
        }
        var shouldMove = false
        if !movable.isEmpty {
            let count = movable.count == 1 ? "1 app" : "\(movable.count) apps"
            let alert = NSAlert()
            alert.messageText = "Move your apps to \(AppsFolder.displayPath(new))?"
            alert.informativeText = """
            \(count) from My Apps \(movable.count == 1 ? "is" : "are") in \(AppsFolder.displayPath(old)). \
            Moving keeps their sign-ins and settings. If you don’t move them, they stay where they \
            are, and Build Apps makes new copies in the new folder.
            """
            alert.addButton(withTitle: "Move Apps")
            alert.addButton(withTitle: "Don’t Move")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn: shouldMove = true
            case .alertSecondButtonReturn: break
            default: return
            }
        }

        AppsFolder.set(new)
        appsFolder = AppsFolder.current
        guard shouldMove else { return }
        let failures = move(movable, from: old, to: new)
        if !failures.isEmpty {
            let report = NSAlert()
            report.alertStyle = .warning
            report.messageText = "Some apps couldn’t be moved"
            report.informativeText = failures.joined(separator: "\n")
                + "\n\nThey’re still in \(AppsFolder.displayPath(old)). Build Apps makes new copies in the new folder."
            report.runModal()
        }
    }

    /// Moves built apps between folders, keeping any subfolders in their names. Returns a
    /// line for each app that couldn't be moved.
    private func move(_ records: [AppRecord], from old: URL, to new: URL) -> [String] {
        let fileManager = FileManager.default
        var failures: [String] = []
        for record in records {
            let source = record.settings.location.bundleURL(in: old)
            let destination = record.settings.location.bundleURL(in: new)
            do {
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: source, to: destination)
                _ = LSRegisterURL(destination as CFURL, true)
                removeIfEmpty(source.deletingLastPathComponent(), within: old)
            } catch {
                failures.append("\(record.settings.location.name): \(error.localizedDescription)")
            }
        }
        return failures
    }

    /// Removes a subfolder (such as /Applications/WebAppWrap) that moving left empty. Never
    /// the apps folder itself.
    private func removeIfEmpty(_ folder: URL, within root: URL) {
        let fileManager = FileManager.default
        var folder = folder.standardizedFileURL
        let root = root.standardizedFileURL
        while folder.path.hasPrefix(root.path + "/") {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: folder.path),
                  contents.allSatisfy({ $0 == ".DS_Store" }),
                  (try? fileManager.removeItem(at: folder)) != nil
            else { return }
            folder = folder.deletingLastPathComponent()
        }
    }

    // MARK: - Finder

    func open(_ app: URL) {
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    func reveal(_ app: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([app])
    }

    func reveal(_ apps: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(apps)
    }
}
