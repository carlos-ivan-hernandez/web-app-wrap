import AppKit
import SwiftUI

/// WebAppWrap → Settings (⌘,): where apps are saved.
struct SettingsView: View {
    @ObservedObject var model: BuilderModel

    var body: some View {
        Form {
            LabeledContent("Save apps in:") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: model.appsFolder.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(AppsFolder.displayPath(model.appsFolder))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(model.appsFolder.path)
                    }
                    HStack(spacing: 8) {
                        Button("Choose…") { model.chooseAppsFolder() }
                        Button("Use Applications") { model.setAppsFolder(AppsFolder.applications) }
                            .disabled(model.appsFolder.path == AppsFolder.applications.path)
                    }
                    .disabled(model.status.isBusy)
                    Text("""
                    Every app you create or build goes here, inside any folders in its name. \
                    When you change it, WebAppWrap offers to move the apps you’ve already built. \
                    The command line uses it too, unless you pass --out.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
