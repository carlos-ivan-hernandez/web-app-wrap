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
        Window("WebAppWrap", id: "main") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .help) {
                HelpMenuItem()
            }
        }

        Window("WebAppWrap Help", id: HelpView.windowID) {
            HelpView()
        }
        .defaultSize(width: 680, height: 760)

        Settings {
            SettingsView(model: model)
        }
    }
}

final class GeneratorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
