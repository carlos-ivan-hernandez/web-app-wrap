import AppKit
import SwiftUI
import WebAppWrapKit

/// This app's browsing history: recorded by tabs, saved to
/// ~/Library/Application Support/<bundle ID>/history.json shortly after each change.
final class HistoryController: ObservableObject {
    @Published private(set) var history: BrowsingHistory
    private let file: URL
    private var pendingSave: DispatchWorkItem?

    init(file: URL = HistoryController.defaultFile) {
        self.file = file
        do {
            history = try BrowsingHistory.load(from: file)
        } catch {
            NSLog("WebAppWrap: couldn’t read history at %@: %@", file.path, error.localizedDescription)
            history = BrowsingHistory()
        }
    }

    static var defaultFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = Bundle.main.bundleIdentifier ?? "WebAppWrapRuntime"
        return support.appendingPathComponent(folder, isDirectory: true).appendingPathComponent("history.json")
    }

    func recordVisit(url: URL?, title: String?) {
        guard let url, BrowsingHistory.isRecordable(url) else { return }
        history.recordVisit(url: url, title: title)
        scheduleSave()
    }

    func updateTitle(_ title: String?, for url: URL?) {
        guard let url else { return }
        let before = history
        history.updateTitle(title, for: url)
        if history != before { scheduleSave() }
    }

    func remove(_ ids: Set<UUID>) {
        history.remove(ids)
        scheduleSave()
    }

    func clear() {
        history.removeAll()
        saveNow()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try history.save(to: file)
        } catch {
            NSLog("WebAppWrap: couldn’t save history: %@", error.localizedDescription)
        }
    }
}

/// The History window: every page visited in this app, searchable. Double-click a page (or
/// select it and press Return) to open it in a new tab.
final class HistoryWindowController: NSWindowController {
    init(history: HistoryController, appName: String, open: @escaping (URL) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(appName) History"
        window.minSize = NSSize(width: 420, height: 300)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentViewController = NSHostingController(rootView: HistoryView(history: history, open: open))
        window.setContentSize(NSSize(width: 640, height: 560))
        window.center()
        // Restores the last size and position, if there is one.
        window.setFrameAutosaveName("WebAppWrapHistoryWindow")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

private struct HistoryView: View {
    @ObservedObject var history: HistoryController
    let open: (URL) -> Void
    @State private var query = ""
    @State private var selection = Set<UUID>()

    private struct Day: Identifiable {
        let id: Date
        let entries: [HistoryEntry]
    }

    private var days: [Day] {
        let calendar = Calendar.current
        var result: [Day] = []
        for entry in history.history.search(query) {
            let day = calendar.startOfDay(for: entry.date)
            if result.last?.id == day {
                result[result.count - 1] = Day(id: day, entries: result[result.count - 1].entries + [entry])
            } else {
                result.append(Day(id: day, entries: [entry]))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search history", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            Divider()

            List(selection: $selection) {
                ForEach(days) { day in
                    Section(Self.dayTitle(day.id)) {
                        ForEach(day.entries) { entry in
                            HistoryRow(entry: entry).tag(entry.id)
                        }
                    }
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if !ids.isEmpty {
                    Button("Open in New Tab") { openEntries(ids) }
                    Button("Copy Link") { copyLinks(ids) }
                    Divider()
                    Button("Remove from History") { history.remove(ids) }
                }
            } primaryAction: { ids in
                openEntries(ids)
            }
            .onDeleteCommand { history.remove(selection) }
            .overlay {
                if history.history.entries.isEmpty {
                    Text("Pages you visit in this app appear here.").foregroundStyle(.secondary)
                } else if days.isEmpty {
                    Text("No pages match “\(query)”.").foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack {
                Text(summary).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear History…") { confirmClear() }
                    .disabled(history.history.entries.isEmpty)
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 420, minHeight: 300)
    }

    private var summary: String {
        let count = history.history.entries.count
        return count == 1 ? "1 visit" : "\(count) visits"
    }

    private func entries(_ ids: Set<UUID>) -> [HistoryEntry] {
        history.history.entries.filter { ids.contains($0.id) }
    }

    private func openEntries(_ ids: Set<UUID>) {
        entries(ids).reversed().forEach { open($0.url) }
    }

    private func copyLinks(_ ids: Set<UUID>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entries(ids).map(\.url.absoluteString).joined(separator: "\n"), forType: .string)
    }

    private func confirmClear() {
        let alert = NSAlert()
        alert.messageText = "Clear all history?"
        alert.informativeText = "This removes every page from this app’s history. You stay signed in."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        selection = []
        history.clear()
    }

    private static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .complete, time: .omitted)
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayTitle).lineLimit(1).truncationMode(.tail)
                Text(entry.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 1)
        .help(entry.url.absoluteString)
    }
}
