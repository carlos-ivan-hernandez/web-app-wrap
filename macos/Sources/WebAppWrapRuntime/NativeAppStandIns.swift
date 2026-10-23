import AppKit
@preconcurrency import WebKit

// Needs the macOS 15.4 SDK (Xcode 16.3, Swift 6.1). See AppDelegate.
#if compiler(>=6.1)

/// Answers messages that extensions send to their desktop app (`runtime.sendNativeMessage`).
/// In Safari these go to a helper that comes with the extension's Mac app. Other apps can't
/// run that helper, so the app answers the messages it can.
///
/// Bitwarden: with a Safari user agent, Bitwarden's Chrome version runs as its Safari
/// version. That version asks its helper ("com.bitwarden.desktop") for a timer, the clipboard,
/// saving files and showing its popup. Unlocking with Touch ID needs Bitwarden's desktop app,
/// so it's reported as unavailable, and Bitwarden offers the master password or PIN instead.
@available(macOS 15.4, *)
@MainActor
enum NativeAppStandIns {
    struct NoAppError: LocalizedError {
        let applicationID: String?
        var errorDescription: String? {
            "There’s no app “\(applicationID ?? "")” for this extension to talk to."
        }
    }

    static func reply(
        to message: Any,
        for applicationID: String?,
        from context: WKWebExtensionContext,
        host: ExtensionHost,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        switch applicationID {
        case "com.bitwarden.desktop":
            bitwarden(message, from: context, host: host, replyHandler: replyHandler)
        default:
            replyHandler(nil, NoAppError(applicationID: applicationID))
        }
    }

    // MARK: - Bitwarden

    /// What Bitwarden's helper (SafariWebExtensionHandler.swift in bitwarden/clients) does.
    private static func bitwarden(
        _ message: Any,
        from context: WKWebExtensionContext,
        host: ExtensionHost,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        guard let message = message as? [String: Any], let command = message["command"] as? String else {
            replyHandler(nil, nil)
            return
        }
        // Biometric answers are wrapped like this, echoing the command and message ID.
        func status(_ response: Any) -> [String: Any] {
            ["message": [
                "command": command,
                "response": response,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "messageId": message["messageId"] ?? NSNull(),
            ]]
        }
        let platformUnsupported = 5 // Bitwarden's BiometricsStatus.PlatformUnsupported

        switch command {
        case "sleep":
            // Bitwarden's timer: the helper answers after 10 seconds.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                replyHandler(nil, nil)
            }
        case "copyToClipboard":
            if declares("clipboardWrite", context), let text = message["data"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            replyHandler(nil, nil)
        case "readFromClipboard":
            let text = declares("clipboardRead", context) ? NSPasteboard.general.string(forType: .string) : nil
            replyHandler(text, nil)
        case "downloadFile":
            saveBitwardenFile(message["data"] as? String)
            replyHandler(nil, nil)
        case "showPopover":
            host.showPopup(for: context)
            replyHandler(nil, nil)
        case "getBiometricsStatus", "getBiometricsStatusForUser":
            replyHandler(status(platformUnsupported), nil)
        case "biometricUnlockAvailable":
            replyHandler(status("not available"), nil)
        case "biometricUnlock":
            replyHandler(status("not supported"), nil)
        case "authenticateWithBiometrics", "unlockWithBiometricsForUser":
            replyHandler(status(false), nil)
        default:
            replyHandler(nil, nil)
        }
    }

    /// An export or attachment: JSON with fileName, blobData (text, or base64 for other types)
    /// and blobOptions.type. Asks where to save it, starting in Downloads.
    private static func saveBitwardenFile(_ json: String?) {
        guard let json, let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let blob = object["blobData"] as? String
        else { return }
        let type = (object["blobOptions"] as? [String: Any])?["type"] as? String
        guard let data = type == "text/plain" ? Data(blob.utf8) : Data(base64Encoded: blob) else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = DownloadManager.safeFilename(object["fileName"] as? String ?? "Bitwarden")
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    /// Whether the extension's manifest asks for `permission`, required or optional. WebKit
    /// doesn't know clipboardRead, so this reads the manifest itself.
    private static func declares(_ permission: String, _ context: WKWebExtensionContext) -> Bool {
        let manifest = context.webExtension.manifest
        return ["permissions", "optional_permissions"].contains { key in
            (manifest[key] as? [Any])?.contains { ($0 as? String) == permission } ?? false
        }
    }
}

#endif
