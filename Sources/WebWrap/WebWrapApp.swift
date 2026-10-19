import AppKit
import SwiftUI

@main
@MainActor
enum Entry {
    static func main() {
        if let status = CommandLineInterface.runIfRequested(CommandLine.arguments) {
            exit(status)
        }
        WebWrapApp.main()
    }
}

struct WebWrapApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: GeneratorAppDelegate
    @StateObject private var model = BuilderModel()

    var body: some Scene {
        Window("WebWrap", id: "main") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Create Apps from JSON…") { model.createAppsFromJSON() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(model.status.isBusy)
            }
        }
    }
}

final class GeneratorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
