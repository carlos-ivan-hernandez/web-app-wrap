import AppKit
import SwiftUI
import WebAppWrapKit

@MainActor
final class BuilderModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case building
        case finished(URL)
        case failed(String)
        /// Building app `current` (1-based) of `total` from the list.
        case buildingList(current: Int, total: Int, name: String)
        case listFinished(created: [URL], failed: Int, skipped: Int)

        var isBusy: Bool {
            switch self {
            case .building, .buildingList: true
            default: false
            }
        }
    }

    enum Mode: String {
        case oneOff
        case list
    }

    @Published var mode = Mode.oneOff
    @Published private(set) var status: Status = .idle
    let oneOff: AppDraft

    let registry = AppRegistry.standard
    /// Every app WebAppWrap has created, plus any added to the list and not built yet.
    @Published private(set) var records: [AppRecord] = []
    /// Set if apps.json couldn't be read. The list isn't saved while this is set, so a
    /// damaged file is never overwritten.
    @Published private(set) var loadError: String?

    init() {
        oneOff = AppDraft()
        do {
            records = try registry.load()
        } catch {
            loadError = "\(registry.listFile.path) couldn’t be read: \(error.localizedDescription)"
        }
        if !records.isEmpty { mode = .list }
    }

    // MARK: - One-off

    var canCreateOneOff: Bool { oneOff.isValid && !status.isBusy }

    /// Builds the one-off form's app, then records it in the list.
    func createApp() {
        let draft = oneOff
        guard canCreateOneOff, let url = draft.normalizedURL else { return }
        let destination = draft.destination

        if FileManager.default.fileExists(atPath: destination.path) {
            let alert = NSAlert()
            alert.messageText = "Replace \(destination.lastPathComponent)?"
            alert.informativeText = "An app already exists at \(destination.path). It will be moved to the Trash. Its sign-ins and settings are kept."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        let spec = AppSpec(displayName: draft.trimmedName, baseURL: url, icon: draft.iconSource, titleBarColor: draft.titleBarHex)
        status = .building
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try AppBuilder.build(spec, to: destination) }
            }.value
            switch result {
            case let .success(app):
                status = .finished(app)
                do {
                    try recordOneOff(draft)
                } catch {
                    status = .failed("Created \(app.lastPathComponent), but it couldn’t be added to your apps: \(error.localizedDescription)")
                }
            case let .failure(error):
                status = .failed(error.localizedDescription)
            }
        }
    }

    /// Adds the app to the list, or updates the entry with the same name, marked as just built.
    private func recordOneOff(_ draft: AppDraft) throws {
        let key = draft.location.key
        let existing = records.first { $0.settings.location.key == key }
        var record = existing ?? AppRecord(settings: AppSettings(name: "", url: ""))
        record.settings = try settings(from: draft, id: record.id, replacing: existing?.settings)
        record.lastBuild = BuildStamp(version: GeneratorVersion.commit, date: Date(), settings: record.settings)
        try store(record)
    }

    // MARK: - The list

    func findRecord(_ id: UUID) -> AppRecord? {
        records.first { $0.id == id }
    }

    func appURL(for record: AppRecord) -> URL {
        record.settings.location.bundleURL(in: AppDraft.applicationsFolder)
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

    /// A message saying why `draft` can't be saved as `id` (nil for a new app), or nil if it can.
    func problem(saving draft: AppDraft, as id: UUID?) -> String? {
        if loadError != nil { return "Your list of apps couldn’t be read, so it can’t be changed." }
        guard draft.isValid else { return "Enter an app name and a web address." }
        let key = draft.location.key
        if records.contains(where: { $0.id != id && $0.settings.location.key == key }) {
            return "Another app in the list already uses \(draft.destination.path)."
        }
        return nil
    }

    /// Saves an added or edited app. Building happens separately.
    func save(_ draft: AppDraft, as id: UUID?) throws {
        if let problem = problem(saving: draft, as: id) {
            throw SaveError(message: problem)
        }
        let existing = id.flatMap(findRecord)
        var record = existing ?? AppRecord(settings: AppSettings(name: "", url: ""))
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

    /// Builds the apps in the list that changed, were built by another version of WebAppWrap,
    /// or are missing. Up-to-date apps are skipped. With `only`, builds just those apps, even
    /// if they're up to date.
    func buildList(only ids: Set<UUID>? = nil) {
        guard !status.isBusy, loadError == nil else { return }
        let candidates = ids.map { ids in records.filter { ids.contains($0.id) } } ?? records
        let targets = ids == nil ? candidates.filter { buildReason(for: $0) != nil } : candidates
        let skipped = records.count - targets.count
        guard !targets.isEmpty else {
            status = .listFinished(created: [], failed: 0, skipped: skipped)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Build \(targets.count) app\(targets.count == 1 ? "" : "s")?"
        var details = targets.prefix(12).map { record in
            let reason = buildReason(for: record).map { " (\($0.description.lowercased()))" } ?? ""
            return record.settings.name + reason
        }.joined(separator: "\n")
        if targets.count > 12 { details += "\n…and \(targets.count - 12) more" }
        if ids == nil, skipped > 0 {
            details += "\n\n\(skipped) app\(skipped == 1 ? " is" : "s are") up to date and will be skipped."
        }
        details += "\n\nApps that already exist are moved to the Trash first. Their sign-ins and settings are kept."
        alert.informativeText = details
        alert.addButton(withTitle: "Build")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let iconsFolder = registry.iconsFolder
        let jobs = targets.compactMap { record in record.batchEntry(iconsFolder: iconsFolder).map { (record, $0) } }
        let root = AppDraft.applicationsFolder
        let version = GeneratorVersion.commit
        status = .buildingList(current: 1, total: jobs.count, name: jobs.first?.1.location.name ?? "")
        Task {
            let results = await Task.detached(priority: .userInitiated) {
                await BatchBuilder.run(jobs.map { $0.1 }, into: root) { index, entry in
                    await MainActor.run {
                        self.status = .buildingList(current: index + 1, total: jobs.count, name: entry.location.name)
                    }
                }
            }.value

            var created: [URL] = []
            var failures: [String] = []
            var updated = records
            for ((record, _), result) in zip(jobs, results) {
                switch result.outcome {
                case let .success(app):
                    created.append(app)
                    if let index = updated.firstIndex(where: { $0.id == record.id }) {
                        updated[index].lastBuild = BuildStamp(version: version, date: Date(), settings: record.settings)
                    }
                case let .failure(error):
                    failures.append("\(record.settings.name): \(error.localizedDescription)")
                }
            }
            // An entry whose web address no longer parses never reaches the builder.
            for record in targets where !jobs.contains(where: { $0.0.id == record.id }) {
                failures.append("\(record.settings.name): “\(record.settings.url)” isn’t a web address.")
            }
            do {
                try registry.save(updated)
                records = updated
            } catch {
                failures.append("The list couldn’t be saved: \(error.localizedDescription)")
            }
            status = .listFinished(created: created, failed: failures.count, skipped: ids == nil ? skipped : 0)

            if !failures.isEmpty {
                let report = NSAlert()
                report.alertStyle = .warning
                report.messageText = "Some apps couldn’t be built"
                report.informativeText = failures.joined(separator: "\n")
                report.runModal()
            }
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
