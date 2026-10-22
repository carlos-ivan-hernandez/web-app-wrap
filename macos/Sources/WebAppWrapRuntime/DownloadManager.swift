import AppKit
@preconcurrency import WebKit

/// Saves downloads to ~/Downloads, like Safari's default.
///
/// WebKit writes the file from its own networking process. macOS can refuse that process access
/// to ~/Downloads ("Operation not permitted") without ever asking the user, because the request
/// doesn't come from the app itself. So WebKit saves into a temporary folder, and the app moves
/// the finished file into Downloads, which macOS lets it ask permission for. If the move is
/// still refused, the user picks where to save it.
final class DownloadManager: NSObject, WKDownloadDelegate {
    private struct Pending {
        let temporaryURL: URL
        let filename: String
    }

    private var pending: [ObjectIdentifier: Pending] = [:]

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let filename = Self.safeFilename(suggestedFilename)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WebAppWrapDownloads", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            completionHandler(nil)
            NSAlert(error: error).runModal()
            return
        }
        let temporaryURL = folder.appendingPathComponent(filename)
        pending[ObjectIdentifier(download)] = Pending(temporaryURL: temporaryURL, filename: filename)
        completionHandler(temporaryURL)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = pending.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let fileManager = FileManager.default
        let downloads = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let destination = Self.uniqueURL(in: downloads, for: item.filename)
        do {
            try fileManager.moveItem(at: item.temporaryURL, to: destination)
            removeTemporaryFolder(of: item)
            Self.announce(destination)
        } catch {
            askWhereToSave(item, after: error)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let item = pending.removeValue(forKey: ObjectIdentifier(download)) {
            removeTemporaryFolder(of: item)
        }
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        NSAlert(error: error).runModal()
    }

    /// Downloads couldn't be written to (usually because access to it was turned off in
    /// System Settings), so the user picks a place. A save panel grants access to what's picked.
    private func askWhereToSave(_ item: Pending, after error: Error) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.filename
        panel.message = "The file couldn’t be saved to Downloads (\(error.localizedDescription)). Choose where to save it."
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            defer { self?.removeTemporaryFolder(of: item) }
            guard response == .OK, let url = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    // The panel already asked whether to replace it.
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
                try FileManager.default.moveItem(at: item.temporaryURL, to: url)
                Self.announce(url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    private func removeTemporaryFolder(of item: Pending) {
        try? FileManager.default.removeItem(at: item.temporaryURL.deletingLastPathComponent())
    }

    /// Bounces the Downloads stack in the Dock, as browsers do.
    private static func announce(_ url: URL) {
        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.apple.DownloadFileFinished"),
            object: url.path
        )
    }

    static func safeFilename(_ suggestedFilename: String) -> String {
        var name = suggestedFilename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.hasPrefix(".") { name = "download" + name }
        return name
    }

    /// "report.pdf", then "report 2.pdf", "report 3.pdf", ...
    static func uniqueURL(in folder: URL, for filename: String) -> URL {
        let name = safeFilename(filename)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }
}
