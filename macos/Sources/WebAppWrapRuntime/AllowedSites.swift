import AppKit
import SwiftUI
import WebAppWrapKit

/// Other sites this app may open, besides its own: links you open with Open Link, and links
/// you click, which otherwise go to your browser. Kept in the app's own defaults, so each
/// app has its own list.
final class AllowedSites: ObservableObject {
    private static let defaultsKey = "AllowedDomains"

    /// Domains such as "github.com", sorted. Each also allows its subdomains.
    @Published private(set) var domains: [String]

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        domains = Array(Set(saved.compactMap(LinkPolicy.normalizeDomain))).sorted()
    }

    /// Adds the domain in `input`. Returns it, or nil if `input` isn't a web address.
    @discardableResult
    func add(_ input: String) -> String? {
        guard let domain = LinkPolicy.normalizeDomain(input) else { return nil }
        if !domains.contains(domain) {
            domains = (domains + [domain]).sorted()
            save()
        }
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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
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
        window.setContentSize(NSSize(width: 460, height: 420))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 300)
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
