import AppKit
import SwiftUI

/// The main window: the list of apps to build (My Apps), and the browser extensions they share.
struct ContentView: View {
    @ObservedObject var model: BuilderModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $model.mode) {
                Text("My Apps").tag(BuilderModel.Mode.list)
                Text("Extensions").tag(BuilderModel.Mode.extensions)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 18)

            switch model.mode {
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

/// "Apps are saved in <folder>", with a Change… link.
struct AppsFolderCaption: View {
    @ObservedObject var model: BuilderModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Text("Apps are saved in \(AppsFolder.displayPath(model.appsFolder))")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.appsFolder.path)
            Button("Change…") { model.chooseAppsFolder() }
                .buttonStyle(.link)
                .disabled(model.status.isBusy)
        }
        .font(.caption)
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

/// Progress and results of the last build.
struct StatusView: View {
    @ObservedObject var model: BuilderModel

    var body: some View {
        switch model.status {
        case .idle:
            EmptyView()
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
