import AppKit
import SwiftUI
import WebAppWrapKit

/// Other sites this app may open, besides its own: links you open with Open Link, and links
/// you click, which otherwise go to your browser. Kept in the app's own defaults, so each
/// app has its own list.
///
/// With Allow All Sites on, every web page opens in the app, and each site visited that isn't
/// on the list is noted in `visited`, so it can be saved to the list later.
final class AllowedSites: ObservableObject {
    private static let defaultsKey = "AllowedDomains"
    private static let allowsAllKey = "AllowAllDomains"
    private static let visitedKey = "DomainsVisitedWhileAllowingAll"

    /// Domains such as "github.com", sorted. Each also allows its subdomains.
    @Published private(set) var domains: [String]

    /// While true, links to any site open in the app.
    @Published var allowsAll: Bool {
        didSet { UserDefaults.standard.set(allowsAll, forKey: Self.allowsAllKey) }
    }

    /// Sites visited while all sites were allowed that aren't on the list, newest first.
    @Published private(set) var visited: [String]

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        domains = Array(Set(saved.compactMap(LinkPolicy.normalizeDomain))).sorted()
        allowsAll = UserDefaults.standard.bool(forKey: Self.allowsAllKey)
        visited = UserDefaults.standard.stringArray(forKey: Self.visitedKey) ?? []
    }

    /// Notes a site visited only because all sites are allowed.
    func noteVisited(_ url: URL) {
        guard let domain = LinkPolicy.domain(of: url), !domains.contains(domain) else { return }
        if visited.first == domain { return }
        visited.removeAll { $0 == domain }
        visited.insert(domain, at: 0)
        if visited.count > 200 { visited.removeLast(visited.count - 200) }
        saveVisited()
    }

    /// Adds visited sites to the list.
    func saveVisited(_ saved: Set<String>) {
        domains = Array(Set(domains).union(saved)).sorted()
        visited.removeAll { saved.contains($0) }
        save()
        saveVisited()
    }

    func dismissVisited(_ dismissed: Set<String>) {
        visited.removeAll { dismissed.contains($0) }
        saveVisited()
    }

    private func saveVisited() {
        UserDefaults.standard.set(visited, forKey: Self.visitedKey)
    }

    /// Adds the domain in `input`. Returns it, or nil if `input` isn't a web address.
    @discardableResult
    func add(_ input: String) -> String? {
        guard let domain = LinkPolicy.normalizeDomain(input) else { return nil }
        if !domains.contains(domain) {
            domains = (domains + [domain]).sorted()
            save()
        }
        if visited.contains(domain) { dismissVisited([domain]) }
        return domain
    }

    func remove(_ removed: Set<String>) {
        domains.removeAll { removed.contains($0) }
        save()
    }

    private func save() {
        UserDefaults.standard.set(domains, forKey: Self.defaultsKey)
    }
}

/// The Allowed Sites window, from the ⋮ menu.
final class AllowedSitesWindowController: NSWindowController {
    init(sites: AllowedSites, appName: String, ownSite: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(appName) Allowed Sites"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentViewController = NSHostingController(
            rootView: AllowedSitesView(sites: sites, appName: appName, ownSite: ownSite)
        )
        window.setContentSize(NSSize(width: 480, height: 600))
        window.center()
        window.setFrameAutosaveName("WebAppWrapAllowedSitesWindow")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

private struct AllowedSitesView: View {
    @ObservedObject var sites: AllowedSites
    let appName: String
    let ownSite: String
    @State private var entry = ""
    @State private var error: String?
    @State private var selection = Set<String>()
    @State private var visitedSelection = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $sites.allowsAll) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow all sites").font(.headline)
                    Text("Every link opens in \(appName) while this is on. Sites you visit are listed below, so you can save them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            Divider()

            Text("""
            \(appName) opens pages on \(ownSite) and the sites below. Links to any other site \
            open in your browser, and Open Link won’t open them. Each site includes its \
            subdomains.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("e.g. github.com", text: $entry)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            List(selection: $selection) {
                ForEach(sites.domains, id: \.self) { domain in
                    Text(domain).tag(domain)
                }
            }
            .contextMenu(forSelectionType: String.self) { domains in
                if !domains.isEmpty {
                    Button("Remove") { remove(domains) }
                }
            }
            .onDeleteCommand { remove(selection) }
            .overlay {
                if sites.domains.isEmpty {
                    Text("No other sites allowed.").foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Remove") { remove(selection) }
                    .disabled(selection.isEmpty)
            }

            if !sites.visited.isEmpty {
                visitedSection
            }
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 300)
    }

    /// Sites visited while all sites were allowed, to save to the list or dismiss.
    private var visitedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Visited while allowing all sites").font(.headline)
            List(selection: $visitedSelection) {
                ForEach(sites.visited, id: \.self) { domain in
                    HStack {
                        Text(domain)
                        Spacer()
                        Button("Save") { saveVisited([domain]) }
                            .controlSize(.small)
                    }
                    .tag(domain)
                }
            }
            .contextMenu(forSelectionType: String.self) { domains in
                if !domains.isEmpty {
                    Button("Save to Allowed Sites") { saveVisited(domains) }
                    Button("Dismiss") { dismissVisited(domains) }
                }
            }
            .onDeleteCommand { dismissVisited(visitedSelection) }
            .frame(minHeight: 100, maxHeight: 180)
            HStack {
                Button("Dismiss All") { dismissVisited(Set(sites.visited)) }
                Spacer()
                Button("Dismiss") { dismissVisited(visitedSelection) }
                    .disabled(visitedSelection.isEmpty)
                Button("Save Selected") { saveVisited(visitedSelection) }
                    .disabled(visitedSelection.isEmpty)
                Button("Save All") { saveVisited(Set(sites.visited)) }
            }
        }
    }

    private func saveVisited(_ domains: Set<String>) {
        sites.saveVisited(domains)
        visitedSelection.subtract(domains)
    }

    private func dismissVisited(_ domains: Set<String>) {
        sites.dismissVisited(domains)
        visitedSelection.subtract(domains)
    }

    private func add() {
        let text = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if sites.add(text) == nil {
            error = "“\(text)” isn’t a site. Enter a domain like github.com."
        } else {
            error = nil
            entry = ""
        }
    }

    private func remove(_ domains: Set<String>) {
        sites.remove(domains)
        selection.subtract(domains)
    }
}
