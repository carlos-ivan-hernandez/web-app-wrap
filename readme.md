# Web App Wrap

Turn any web app into its own native desktop app, with real tabs.

Give Web App Wrap a name, a web address, and optionally an image. It creates an
app with its own icon, its own window and taskbar or Dock entry, and its own
sign-ins and storage. Inside the app:

- Ctrl+T / ⌘T opens a new tab, and Ctrl+click / ⌘-click opens a link in a new
  tab.
- Ctrl+W / ⌘W closes the tab.
- Links to other sites open in your default browser.

Web App Wrap has a window for making apps one at a time, a JSON batch format for
making many at once, and a command-line tool.

| Platform | Built with | Folder |
| --- | --- | --- |
| macOS 13+ | Swift, AppKit, SwiftUI, WKWebView | [macos](macos) |
| Windows 10 (1809+) and 11 | C# / .NET 10, WinUI 3 (Windows App SDK), WebView2 | [windows](windows) |

A separate project, **web-app-wrap-node**, runs your apps straight from
`npm start` instead of creating installed apps. It uses the same JSON config
format.

Each folder has its own readme with build steps, usage, and the
command-line reference. Both versions share the same app inputs and JSON
format, and route links the same way.

Source code and issues: https://github.com/carlos-ivan-hernandez/web-app-wrap
