import AppKit
import SwiftUI

/// The main window: make one app now (One-Off), or keep a list of apps and build them (My Apps).
struct ContentView: View {
    @ObservedObject var model: BuilderModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $model.mode) {
                Text("One-Off").tag(BuilderModel.Mode.oneOff)
                Text("My Apps").tag(BuilderModel.Mode.list)
                Text("Extensions").tag(BuilderModel.Mode.extensions)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 18)

            switch model.mode {
            case .oneOff: OneOffView(model: model, draft: model.oneOff)
            case .list: AppListView(model: model)
            case .extensions: ExtensionsView(model: model)
            }
        }
        .frame(width: 620)
        // Apps can turn extensions on and off from their own Extensions menu.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reloadExtensions()
        }
    }
}

/// Fill in the form and create one app. It's added to My Apps too.
struct OneOffView: View {
    @ObservedObject var model: BuilderModel
    @ObservedObject var draft: AppDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            AppForm(draft: draft) { model.createApp() }
                .disabled(model.status.isBusy)
            Divider()
            HStack(spacing: 10) {
                HelpButton()
                StatusView(model: model)
                Spacer()
                Button("Create App") { model.createApp() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canCreateOneOff)
            }
            .frame(minHeight: 28)
        }
        .padding(24)
    }
}

struct HelpButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button { openWindow(id: HelpView.windowID) } label: {
            Image(systemName: "questionmark.circle")
        }
        .buttonStyle(.borderless)
        .help("WebAppWrap Help")
    }
}

/// Progress and results of the last build, shared by both modes.
struct StatusView: View {
    @ObservedObject var model: BuilderModel

    var body: some View {
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
        case let .buildingList(current, total, name):
            ProgressView().controlSize(.small)
            Text("Building \(current) of \(total): \(name)…")
                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        case let .listFinished(created, failed, skipped):
            Image(systemName: failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(failed == 0 ? .green : .orange)
            Text(Self.summary(created: created.count, failed: failed, skipped: skipped))
                .lineLimit(1)
            if !created.isEmpty {
                Button("Show in Finder") { model.reveal(created) }
            }
        }
    }

    private static func summary(created: Int, failed: Int, skipped: Int) -> String {
        if created == 0, failed == 0 { return "All apps are up to date" }
        var parts = ["Built \(created)"]
        if failed > 0 { parts.append("\(failed) failed") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        return parts.joined(separator: ", ")
    }
}
