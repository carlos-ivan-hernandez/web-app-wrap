import SwiftUI

/// The Help window: what the tool is for, the window vs. the command line, and the CLI reference.
struct HelpView: View {
    static let windowID = "help"
    static let repositoryURL = URL(string: "https://github.com/carlos-ivan-hernandez/web-app-wrap")!
    private static let executablePath = "/Applications/WebAppWrap.app/Contents/MacOS/WebAppWrap"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header
                overview
                twoWays
                commandLine
                batchFormat
                generatedApps
                footer
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            // Fill the window's width so the text rewraps as the window is resized.
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text("WebAppWrap Help").font(.title.bold())
                Text("Turn any web app into a native Mac app with tabs.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var overview: some View {
        section("What it’s for") {
            paragraph("""
            WebAppWrap creates a separate Mac app for a website. Each app has its own Dock icon, \
            its own window, and its own sign-ins and storage, so a web app you use every day \
            behaves like a native app instead of one more browser tab.
            """)
            paragraph("Inside a wrapped app:")
            bullets([
                "⌘T opens a new tab at the app’s address; ⌘W closes the tab (closing the last one quits).",
                "⌘-click opens a link in a new tab; ⌘H and ⌘L switch to the previous and next tab.",
                "Drag tabs to reorder them. Tabs appear once two or more are open.",
                "Links to other websites open in your default browser.",
                "⌥⌘I opens Web Inspector for debugging.",
            ])
        }
    }

    private var twoWays: some View {
        section("Two ways to use it") {
            paragraph("**The window** (this app). In **One-Off**, fill in the fields and click **Create App**:")
            bullets([
                "**App name**: shown in the Dock and menu bar. Add folders with “/”: “WebAppWrap/Photos” saves Photos.app in /Applications/WebAppWrap.",
                "**Web address**: where new tabs open.",
                "**Icon image** (optional): a square image, rounded to the macOS icon shape. Any solid or transparent border is cropped off automatically; the slider zooms in further.",
                "**Title bar color**: filled in from the site’s theme color; pick another to override it.",
            ])
            paragraph("""
            **My Apps** lists every app made in this window, including one-offs. Add apps with **+**, \
            double-click one to change it, then click **Build Apps** to see what will be built and why, \
            and click **Build** there to start. An app is skipped when nothing about \
            it changed and it was built by this version of WebAppWrap (\(GeneratorVersion.display)), so \
            after updating WebAppWrap, Build Apps rebuilds them all.
            """)
            paragraph("""
            The list and the icon images are kept in ~/Library/Application Support/WebAppWrap, so you \
            don’t need the original image files again. A replaced icon is moved to the previous-icons folder there.
            """)
            paragraph("""
            **Extensions** installs browser extensions once for every app: import them from Chrome \
            (or Brave, Edge, Helium, Vivaldi, Arc, Opera and other Chromium browsers; the Browsers \
            menu chooses which are listed), or add an unpacked folder, .zip or .crx. Each extension is \
            on for all apps until you change it, by double-clicking it or in an app’s Edit sheet. \
            Apps pick up changes when you switch to them, with no rebuild, and have an Extensions menu \
            of their own. Extensions need macOS 15.4 or later.
            """)
            paragraph("**The command line.** The same features, for scripts and automation. See below.")
        }
    }

    private var commandLine: some View {
        section("Command line") {
            paragraph("The command-line tool is inside the app bundle:")
            code(Self.executablePath)
            paragraph("For convenience, add an alias to your shell profile (e.g. ~/.zshrc):")
            code(#"alias webappwrap="/Applications/WebAppWrap.app/Contents/MacOS/WebAppWrap""#)

            command(
                "build",
                usage: "webappwrap build --name <name> --url <address> [--image <file>] [--zoom <1-3>] [--title-bar-color <#RRGGBB>] [--out <folder>]",
                summary: "Creates one app.",
                options: [
                    .init("--name", "App name. May include folders, e.g. \"WebAppWrap/Photos\". Required."),
                    .init("--url", "Web address. https:// is added if missing. Required."),
                    .init("--image", "Icon image. Without it, a colored tile with the name’s first letter is drawn."),
                    .init("--zoom", "1–3, on top of the automatic zoom that crops off the image’s border. Default 1."),
                    .init("--no-auto-zoom", "Use the image as it is, without cropping off its border."),
                    .init("--title-bar-color", "Hex color such as #1a1a1a. Default: the site’s theme color."),
                    .init("--out", "Folder the app (and any folders in its name) go in. Default /Applications."),
                ],
                example: #"webappwrap build --name "Linear" --url linear.app --image ~/Pictures/linear.png"#
            )

            command(
                "batch",
                usage: "webappwrap batch <file.json> [--out <folder>]",
                summary: "Creates every app listed in a JSON file (format below). The whole file is checked first; one failing app doesn’t stop the others. Exits with status 1 if any app failed.",
                options: [.init("--out", "Folder the apps go in. Default /Applications.")],
                example: "webappwrap batch ~/apps.json"
            )

            command(
                "icon",
                usage: "webappwrap icon --name <name> [--image <file>] [--zoom <1-3>] [--symbol <sf-symbol>] --out <file.icns>",
                summary: "Writes just the .icns icon, using the same rules as build.",
                options: [
                    .init("--symbol", "Draw an SF Symbol (e.g. globe) on the default tile instead of a letter."),
                    .init("--out", "Where to write the .icns file. Required."),
                ],
                example: #"webappwrap icon --name "Linear" --out Linear.icns"#
            )

            paragraph("Run `webappwrap help` to print a summary of these commands.")
        }
    }

    private var batchFormat: some View {
        section("Batch file format") {
            paragraph("For the batch command: a JSON array of objects with the same inputs as the window. Only name and url are required. JSONC and JSON5 work too, so you can add comments, trailing commas, unquoted keys and single quotes.")
            code("""
            [
              {
                "name": "WebAppWrap/Photos",
                "url": "https://kphotos.vercel.app",
                "image": "icons/photos.png",
                "zoom": 1.2,
                "titleBarColor": "#1a1a1a"
              },
              { "name": "Linear", "url": "linear.app" }
            ]
            """)
            bullets([
                "**image**: relative to the JSON file unless it starts with / or ~.",
                "**zoom**: 1–3, on top of the automatic border crop.",
                "**titleBarColor**: defaults to the site’s theme color.",
            ])
        }
    }

    private var generatedApps: some View {
        section("Good to know") {
            bullets([
                "Recreating an app with the same name replaces it (the old copy goes to the Trash) and keeps its sign-ins.",
                "Apps are signed for this Mac only. To run one on another Mac, right-click it and choose Open the first time.",
                "Sites served over https can’t call http:// servers from inside a wrapped app; serve them over https too.",
            ])
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(.secondary)
                Text("Source code, issues and updates:")
                Link("github.com/carlos-ivan-hernandez/web-app-wrap", destination: Self.repositoryURL)
            }
            .font(.callout)
            Text("Version \(GeneratorVersion.display)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Building blocks

    private struct Option: Identifiable {
        let flag: String
        let meaning: String
        var id: String { flag }

        init(_ flag: String, _ meaning: String) {
            self.flag = flag
            self.meaning = meaning
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.semibold))
            content()
        }
    }

    private func paragraph(_ markdown: String) -> some View {
        Text(LocalizedStringKey(markdown))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("•").foregroundStyle(.secondary)
                    Text(LocalizedStringKey(item))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func code(_ text: String) -> some View {
        Text(text)
            .font(.system(.callout, design: .monospaced))
            .lineSpacing(3)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func command(
        _ name: String,
        usage: String,
        summary: String,
        options: [Option],
        example: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(name).font(.title3.monospaced().weight(.semibold))
            paragraph(summary)
            code(usage)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
                ForEach(options) { option in
                    GridRow {
                        Text(option.flag).font(.system(.callout, design: .monospaced))
                        Text(option.meaning)
                            .font(.callout)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("Example").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            code(example)
        }
        .padding(.top, 10)
    }
}

/// Help menu item. A View so it can use `openWindow`.
struct HelpMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("WebAppWrap Help") { openWindow(id: HelpView.windowID) }
        Divider()
        Link("WebAppWrap on GitHub", destination: HelpView.repositoryURL)
    }
}
