import AppKit
import CoreLocation
import WebKit

/// Lets pages use the Mac's location (navigator.geolocation). The app's own site and its
/// allowed sites may; other sites may not. macOS asks once whether the app may use location,
/// and it can be changed in System Settings → Privacy & Security → Location Services.
final class LocationAccess {
    private unowned let appDelegate: AppDelegate
    private let manager = CLLocationManager()
    /// The "turned off in System Settings" message is shown once per launch.
    private var hasExplainedTurnedOff = false

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    /// Whether a page from `origin` may have the location.
    func allows(_ origin: WKSecurityOrigin) -> Bool {
        var components = URLComponents()
        components.scheme = origin.protocol
        components.host = origin.host
        if origin.port != 0 { components.port = origin.port }
        guard let url = components.url, appDelegate.linkPolicy.isInternal(url) else { return false }

        switch manager.authorizationStatus {
        case .notDetermined:
            // macOS shows its own prompt; WebKit then waits for the answer.
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            explainTurnedOff(site: origin.host)
        default:
            break
        }
        return true
    }

    private func explainTurnedOff(site: String) {
        guard !hasExplainedTurnedOff else { return }
        hasExplainedTurnedOff = true
        let appName = appDelegate.config.appName
        let alert = NSAlert()
        alert.messageText = "Location for \(appName) is turned off in System Settings"
        alert.informativeText = "\(site) asked for your location. To share it, allow \(appName) in System Settings → Privacy & Security → Location Services."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }
}
