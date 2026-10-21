import AppKit
import SwiftUI
import WebAppWrapKit

/// My Apps: every app WebAppWrap has created. Add or edit apps, then build the ones that
/// changed or were built by another version of WebAppWrap.
struct AppListView: View {
    @ObservedObject var model: BuilderModel
    @State private var selection: UUID?
    @State private var editing: EditorTarget?

    /// What the add/edit sheet is showing. A new draft each time the sheet opens.
    struct EditorTarget: Identifiable {
        let id = UUID()
        /// A fresh ID when adding an app.
        let recordID: UUID
        let isNew: Bool
        let draft: AppDraft
    }

    private var pendingCount: Int {
        model.records.filter { model.buildReason(for: $0) != nil }.count
    }

    var body: some View {
        if let plan = model.buildPlan {
            BuildReviewView(model: model, plan: plan)
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = model.loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            List(selection: $selection) {
                ForEach(model.records) { record in
                    AppRow(record: record, reason: model.buildReason(for: record), iconURL: model.iconURL(for: record))
                        .tag(record.id)
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first {
                    Button("Edit…") { edit(id) }
                    Button("Build…") { model.reviewBuild(only: [id]) }
                        .disabled(model.status.isBusy)
                    if let record = model.findRecord(id) {
                        let app = model.appURL(for: record)
                        if FileManager.default.fileExists(atPath: app.path) {
                            Button("Open") { model.open(app) }
                            Button("Show in Finder") { model.reveal(app) }
                        }
                    }
                    Divider()
                    Button("Remove from List…") { confirmRemove(id) }
                }
            } primaryAction: { ids in
                if let id = ids.first { edit(id) }
            }
            .onDeleteCommand { if let selection { confirmRemove(selection) } }
            .frame(height: 340)
            .overlay {
                if model.records.isEmpty && model.loadError == nil {
                    Text("No apps yet. Click + to add one, or create a one-off app.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Button { add() } label: { Image(systemName: "plus") }
                    .help("Add an app")
                Button { if let selection { confirmRemove(selection) } } label: { Image(systemName: "minus") }
                    .help("Remove the selected app from the list")
                    .disabled(selection == nil)
                Button("Edit…") { if let selection { edit(selection) } }
                    .disabled(selection == nil)
                Spacer()
                Text(countSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .disabled(model.status.isBusy || model.loadError != nil)

            Divider()

            HStack(spacing: 10) {
                HelpButton()
                StatusView(model: model)
                Spacer()
                Button(pendingCount == 0 ? "Build Apps" : "Build \(pendingCount) App\(pendingCount == 1 ? "" : "s")…") {
                    model.reviewBuild()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pendingCount == 0 || model.status.isBusy || model.loadError != nil)
                .help("Shows the apps that changed, were built by another version of WebAppWrap, or are missing, then builds them. Up-to-date apps are skipped.")
            }
            .frame(minHeight: 28)
        }
        .padding(24)
        .sheet(item: $editing) { target in
            AppEditorSheet(model: model, recordID: target.recordID, isNew: target.isNew, draft: target.draft)
        }
    }

    private var countSummary: String {
        let total = model.records.count
        guard total > 0 else { return "WebAppWrap \(GeneratorVersion.display)" }
        let pending = pendingCount
        let upToDate = total - pending
        return "\(total) app\(total == 1 ? "" : "s") · \(upToDate) up to date · WebAppWrap \(GeneratorVersion.display)"
    }

    private func add() {
        editing = EditorTarget(recordID: UUID(), isNew: true, draft: AppDraft())
    }

    private func edit(_ id: UUID) {
        guard !model.status.isBusy, let record = model.findRecord(id) else { return }
        editing = EditorTarget(recordID: id, isNew: false, draft: AppDraft(settings: record.settings, iconURL: model.iconURL(for: record)))
    }

    private func confirmRemove(_ id: UUID) {
        guard !model.status.isBusy, let record = model.findRecord(id) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(record.settings.location.name) from the list?"
        alert.informativeText = "The app stays in Applications. Its icon is moved to the previous-icons folder."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try model.remove(id)
            if selection == id { selection = nil }
        } catch {
            let failure = NSAlert(error: error)
            failure.runModal()
        }
    }
}

/// One app in the list: its icon, name, address and whether the next build will rebuild it.
private struct AppRow: View {
    let record: AppRecord
    let reason: AppRecord.BuildReason?
    let iconURL: URL?
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().interpolation(.high)
                } else {
                    Color.clear
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.settings.name).lineLimit(1).truncationMode(.middle)
                Text(record.settings.url).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let reason {
                Label(reason.description, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                Label("Up to date", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .help(buildHelp)
        .task(id: record.settings) {
            thumbnail = IconRenderer.nsImage(iconSource, pixels: 64)
        }
    }

    private var iconSource: IconSource {
        if let iconURL, let image = NSImage(contentsOf: iconURL), image.isValid {
            return .image(image, zoom: IconRenderer.automaticZoom(for: image) * CGFloat(record.settings.zoom))
        }
        return .generated(name: record.settings.location.name)
    }

    private var buildHelp: String {
        guard let lastBuild = record.lastBuild else { return "Not built yet" }
        let date = lastBuild.date.formatted(date: .abbreviated, time: .shortened)
        return "Last built \(date) with WebAppWrap \(GeneratorVersion.describe(lastBuild.version))"
    }
}

/// Adds an app to the list, or edits one. Saving doesn't build; Build Apps does.
struct AppEditorSheet: View {
    @ObservedObject var model: BuilderModel
    let recordID: UUID
    let isNew: Bool
    @ObservedObject var draft: AppDraft
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    /// Extension ID -> on or off for this app, saved with the app.
    @State private var extensionStates: [String: Bool] = [:]
    @State private var initialExtensionStates: [String: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isNew ? "Add App" : "Edit App").font(.title2.weight(.semibold))
            AppForm(draft: draft) { save() }
            if let note = renameNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if !model.extensions.isEmpty {
                extensionSwitches
            }
            Divider()
            HStack(spacing: 10) {
                if let error {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isValid)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear {
            extensionStates = Dictionary(uniqueKeysWithValues: model.extensions.map { ($0.id, $0.isEnabled(forApp: recordID)) })
            initialExtensionStates = extensionStates
        }
    }

    private var extensionSwitches: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Extensions").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(model.extensions) { installed in
                    Toggle(installed.name, isOn: Binding(
                        get: { extensionStates[installed.id] ?? installed.isEnabled(forApp: recordID) },
                        set: { extensionStates[installed.id] = $0 }
                    ))
                    .lineLimit(1)
                }
            }
            Text("Changes take effect the next time you switch to the app. No rebuild needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Renaming points the list at a new app; the one built under the old name isn't removed.
    private var renameNote: String? {
        guard !isNew, let record = model.findRecord(recordID), record.lastBuild != nil else { return nil }
        let old = model.appURL(for: record)
        guard record.settings.location.key != draft.location.key, FileManager.default.fileExists(atPath: old.path) else { return nil }
        return "Renaming doesn’t remove \(old.path). Delete it yourself if you no longer want it."
    }

    private func save() {
        do {
            try model.save(draft, as: recordID)
            // Only the switches changed here, so changes made meanwhile from an app's menu are kept.
            model.setExtensions(extensionStates.filter { initialExtensionStates[$0.key] != $0.value }, forApp: recordID)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
