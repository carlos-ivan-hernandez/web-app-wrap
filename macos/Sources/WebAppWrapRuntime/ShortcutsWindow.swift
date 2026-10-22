import AppKit
import SwiftUI

/// The Keyboard Shortcuts window, from the ⋮ menu and the app menu.
final class ShortcutsWindowController: NSWindowController {
    init(store: ShortcutStore, appName: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(appName) Keyboard Shortcuts"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentViewController = NSHostingController(rootView: ShortcutsView(store: store, appName: appName))
        window.setContentSize(NSSize(width: 560, height: 640))
        window.center()
        window.setFrameAutosaveName("WebAppWrapShortcutsWindow")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

private struct ShortcutsView: View {
    @ObservedObject var store: ShortcutStore
    let appName: String

    /// The command waiting for a key press, and whether the press replaces its shortcuts or adds one.
    @State private var recording: (id: String, adds: Bool)?
    @State private var monitor: Any?
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Click Change, then press the new shortcut. A shortcut needs ⌘, ⌃ or ⌥ (F keys work alone). Press ⎋ to cancel, or ⌫ to remove the command’s shortcuts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(ShortcutCommand.sections, id: \.self) { section in
                    Section(section == "App" ? appName : section) {
                        ForEach(ShortcutCommand.all.filter { $0.section == section }, id: \.id) { command in
                            row(command)
                        }
                    }
                }
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(messageIsError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Edit menu shortcuts (⌘C, ⌘V and so on) can’t be changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") {
                    stopRecording()
                    store.resetAll()
                    show("All shortcuts are back to their defaults.")
                }
                .disabled(store.overrides.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 360)
        .onDisappear(perform: stopRecording)
    }

    private func row(_ command: ShortcutCommand) -> some View {
        let shortcuts = store.shortcuts(for: command)
        let isRecording = recording?.id == command.id
        return HStack(spacing: 8) {
            Text(command.title)
            if store.isCustomized(command) {
                Text("changed").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if isRecording {
                Text(recording?.adds == true ? "Press another shortcut…" : "Press the new shortcut…")
                    .foregroundStyle(Color.accentColor)
            } else if shortcuts.isEmpty {
                Text("None").foregroundStyle(.tertiary)
            } else {
                ForEach(shortcuts, id: \.self) { shortcut in
                    Text(shortcut.display)
                        .font(.system(.body, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
                }
            }
            if isRecording {
                Button("Cancel", action: stopRecording).controlSize(.small)
            } else {
                Button("Change") { startRecording(command, adds: false) }.controlSize(.small)
                Menu {
                    Button("Add Another Shortcut") { startRecording(command, adds: true) }
                    Button("Remove Shortcuts") {
                        store.set([], for: command)
                        show("\(command.title) has no shortcut now.")
                    }
                    .disabled(shortcuts.isEmpty)
                    Button("Restore Default") {
                        store.reset(command)
                        show("\(command.title) is back to \(describe(command.defaults)).")
                    }
                    .disabled(!store.isCustomized(command))
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private func describe(_ shortcuts: [KeyShortcut]) -> String {
        shortcuts.isEmpty ? "no shortcut" : shortcuts.map(\.display).joined(separator: ", ")
    }

    private func show(_ text: String, error: Bool = false) {
        message = text
        messageIsError = error
    }

    /// Listens for the next key press. A local monitor sees it before the menus do, so pressing
    /// ⌘W here sets a shortcut instead of closing the window.
    private func startRecording(_ command: ShortcutCommand, adds: Bool) {
        stopRecording()
        recording = (command.id, adds)
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, for: command, adds: adds)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }

    private func handle(_ event: NSEvent, for command: ShortcutCommand, adds: Bool) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers.isEmpty, event.keyCode == 53 { // Escape
            stopRecording()
            return
        }
        if modifiers.isEmpty, event.keyCode == 51 || event.keyCode == 117 { // Delete, Forward Delete
            stopRecording()
            store.set([], for: command)
            show("\(command.title) has no shortcut now.")
            return
        }
        guard let shortcut = KeyShortcut(event: event) else {
            show("A shortcut needs ⌘, ⌃ or ⌥ (F keys work alone). Try again, or press ⎋ to cancel.", error: true)
            return
        }
        if let taken = ShortcutStore.reserved[shortcut] {
            show("\(shortcut.display) is \(taken), which can’t be changed. Try another, or press ⎋ to cancel.", error: true)
            return
        }
        stopRecording()
        let shortcuts = adds ? store.shortcuts(for: command) + [shortcut] : [shortcut]
        let takenFrom = store.set(shortcuts, for: command)
        if takenFrom.isEmpty {
            show("\(command.title): \(describe(store.shortcuts(for: command))).")
        } else {
            let names = takenFrom.map(\.title).joined(separator: ", ")
            show("\(command.title): \(shortcut.display). It was removed from \(names).")
        }
    }
}
