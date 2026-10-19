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

    var body: some Scene {
        Window("WebWrap", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

final class GeneratorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
