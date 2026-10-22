import AppKit
import SwiftUI
@preconcurrency import WebKit

/// A set of cookies, logins and site storage. Each window uses one profile, so the same site
/// can be signed in to different accounts in different windows.
struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
}

/// The app's profiles, kept in its own defaults. The first one, the default profile, uses the
/// website data the app had before profiles existed, so existing logins stay. Others each have
/// their own data store, which needs macOS 14.
final class Profiles: ObservableObject {
    private static let defaultsKey = "Profiles"
    private static let lastUsedKey = "LastUsedProfile"
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    @Published private(set) var list: [Profile]
    var onChange: (() -> Void)?
    private var stores: [UUID: WKWebsiteDataStore] = [:]

    static var isSupported: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    init() {
        var saved: [Profile] = []
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([Profile].self, from: data) {
            saved = decoded
        }
        if !Self.isSupported { saved = saved.filter { $0.id == Self.defaultID } }
        if !saved.contains(where: { $0.id == Self.defaultID }) {
            saved.insert(Profile(id: Self.defaultID, name: "Default"), at: 0)
        }
        list = saved
    }

    /// More than one profile, so windows show which one they use.
    var hasSeveral: Bool { list.count > 1 }

    func profile(_ id: UUID) -> Profile {
        list.first { $0.id == id } ?? list[0]
    }

    func name(of id: UUID) -> String {
        profile(id).name
    }

    /// The profile the last focused window used, for the first window at launch.
    var lastUsed: UUID {
        get {
            let id = UserDefaults.standard.string(forKey: Self.lastUsedKey).flatMap(UUID.init(uuidString:))
            return id.flatMap { id in list.contains { $0.id == id } ? id : nil } ?? Self.defaultID
        }
        set { UserDefaults.standard.set(newValue.uuidString, forKey: Self.lastUsedKey) }
    }

    func dataStore(for id: UUID) -> WKWebsiteDataStore {
        guard id != Self.defaultID, list.contains(where: { $0.id == id }) else { return .default() }
        if let store = stores[id] { return store }
        if #available(macOS 14.0, *) {
            let store = WKWebsiteDataStore(forIdentifier: id)
            stores[id] = store
            return store
        }
        return .default()
    }

    @discardableResult
    func add(named name: String) -> Profile {
        let profile = Profile(id: UUID(), name: uniqueName(name))
        list.append(profile)
        save()
        return profile
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = list.firstIndex(where: { $0.id == id }) else { return }
        list[index].name = trimmed
        save()
    }

    /// Deletes the profile and its cookies and site data. Its windows must be closed first.
    func remove(_ id: UUID, completion: @escaping (Error?) -> Void) {
        guard id != Self.defaultID else { return }
        list.removeAll { $0.id == id }
        stores.removeValue(forKey: id)
        save()
        guard #available(macOS 14.0, *) else {
            completion(nil)
            return
        }
        // WebKit refuses while a web view still uses the store; closed tabs take a moment to go.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            WKWebsiteDataStore.remove(forIdentifier: id) { error in
                completion(error)
            }
        }
    }

    /// "Work", or "Work 2" if there's already a "Work".
    func uniqueName(_ name: String) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Profile" : name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(list.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }

    private func save() {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        onChange?()
    }
}

/// The Manage Profiles window, from the ⋮ menu.
final class ProfilesWindowController: NSWindowController {
    init(appDelegate: AppDelegate) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(appDelegate.config.appName) Profiles"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentViewController = NSHostingController(rootView: ProfilesView(
            profiles: appDelegate.profiles,
            appName: appDelegate.config.appName,
            open: { [weak appDelegate] id in appDelegate?.showProfile(id) },
            add: { [weak appDelegate] in appDelegate?.newProfile(nil) },
            remove: { [weak appDelegate] id in appDelegate?.confirmRemoveProfile(id) }
        ))
        window.setContentSize(NSSize(width: 440, height: 420))
        window.center()
        window.setFrameAutosaveName("WebAppWrapProfilesWindow")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

private struct ProfilesView: View {
    @ObservedObject var profiles: Profiles
    let appName: String
    let open: (UUID) -> Void
    let add: () -> Void
    let remove: (UUID) -> Void
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("""
            Each profile keeps its own logins, cookies and site data, so you can be signed in to \
            different accounts in different windows. New windows use the profile of the window \
            you’re in.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if !Profiles.isSupported {
                Text("More profiles need macOS 14 or later.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            List(selection: $selection) {
                ForEach(profiles.list) { profile in
                    ProfileRow(profile: profile, isDefault: profile.id == Profiles.defaultID) { name in
                        profiles.rename(profile.id, to: name)
                    }
                    .tag(profile.id)
                }
            }

            HStack {
                Button("New Profile…", action: add)
                    .disabled(!Profiles.isSupported)
                Button("Delete…") {
                    if let selection { remove(selection) }
                }
                .disabled(selection == nil || selection == Profiles.defaultID)
                Spacer()
                Button("Open Window") {
                    if let selection { open(selection) }
                }
                .disabled(selection == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 360, minHeight: 280)
    }
}

/// A profile's name, editable in place.
private struct ProfileRow: View {
    let profile: Profile
    let isDefault: Bool
    let rename: (String) -> Void
    @State private var name = ""

    var body: some View {
        HStack {
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .onSubmit { commit() }
            if isDefault {
                Text("default").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { name = profile.name }
        .onChange(of: profile.name) { name = $0 }
        .onDisappear { commit() }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            name = profile.name
        } else if trimmed != profile.name {
            rename(trimmed)
        }
    }
}
