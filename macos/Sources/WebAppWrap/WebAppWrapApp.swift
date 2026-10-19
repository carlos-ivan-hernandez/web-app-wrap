import AppKit
import SwiftUI

@main
@MainActor
enum Entry {
    static func main() {
        if let status = CommandLineInterface.runIfRequested(CommandLine.arguments) {
            exit(status)
        }
        WebAppWrapApp.main()
    }
}

struct WebAppWrapApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: GeneratorAppDelegate
    @StateObject private var model = BuilderModel()

    var body: some Scene {
        Window("Web App Wrap", id: "main") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .help) {
                HelpMenuItem()
            }
            CommandGroup(after: .newItem) {
                Button("Create Apps from JSON…") { model.createAppsFromJSON() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(model.status.isBusy)
            }
        }

        Window("Web App Wrap Help", id: HelpView.windowID) {
            HelpView()
        }
        .defaultSize(width: 680, height: 760)
    }
}

final class GeneratorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
