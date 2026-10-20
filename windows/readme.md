# Web App Wrap for Windows

A native Windows app that turns any web app into its own Windows app, with real
tabs.

Give it a name, a web address, and optionally an image. It creates an app with
the following:

- a Start menu entry
- its own taskbar button and icon (pinnable separately)
- its own window
- its own cookies and sign-ins

This is the Windows version, built with WinUI 3 (Windows App SDK) and WebView2.
The macOS version is in [../macos](../macos). Run the commands below from this
`windows` folder.

## Tabs in wrapped apps

The window has a single bar at the top, in the title-bar color you pick, with
the minimize, maximize and close buttons on the right. With one tab open, that's
all it shows. With two or more, tabs up to 240px wide sit in the bar. Every tab
uses the bar's color, thin dividers separate them, and the selected tab has
brighter text.

| Action | Result |
| --- | --- |
| Ctrl+T, or the `+` after the last tab | New tab at the base URL |
| Ctrl+click a link | Opens in a new background tab |
| Ctrl+Shift+click a link | Opens in a new tab and switches to it |
| Ctrl+W, or the tab's × | Closes the tab. Closing the last tab closes the window |
| Ctrl+Shift+W | Closes the window and all its tabs |
| Ctrl+N | New window |
| Ctrl+H / Ctrl+L | Previous / next tab (Ctrl+Shift+Tab / Ctrl+Tab also work) |
| Ctrl+1 … Ctrl+8, Ctrl+9 | Go to tab N, or to the last tab |
| Drag a tab sideways | Reorder tabs |
| Drag the bar's empty space | Move the window (snap layouts work as usual) |
| Alt+← / Alt+→, F5, Ctrl+plus / Ctrl+minus / Ctrl+0 | Back / forward, reload, zoom (WebView2's built-in keys) |
| F12, or right-click → Inspect | Developer tools |

### Which links stay in the app

The routing works the same way as on macOS:

- **In the app:** the base URL's host and its subdomains (`www.` is ignored).
- **In your default browser:** any clicked link to a different host.
- **In the app that handles the link:** `mailto:`, `tel:`, `zoommtg:` and other
  non-web links.

Redirects and script-driven navigation to other hosts stay in the app, so
single sign-on (SSO) and OAuth sign-in work. A sign-in popup a script opens
with a set size, such as "Sign in with Google", opens in a tab inside the app.
That lets it report back to the page that opened it.

Downloads, file uploads, permission prompts and printing use WebView2's
built-in UI, the same as Microsoft Edge's.

## Requirements

- Windows 10 version 1809 or later, or Windows 11, on x64 or ARM64.
- The WebView2 Runtime. It's included with Windows 11 and installed with
  Microsoft Edge on Windows 10.
- To build: the [.NET 10 SDK](https://dotnet.microsoft.com/download). Visual
  Studio 2022 or later with the "WinUI application development" workload
  works too, but isn't required.

The built app is self-contained, so the computers it runs on don't need .NET
or the Windows App SDK runtime installed.

## Build and install

In PowerShell:

```powershell
.\scripts\build.ps1                 # builds "dist\Web App Wrap"
.\scripts\build.ps1 -Install        # also installs it for the current user
.\scripts\build.ps1 -Arch arm64     # for ARM64 PCs
```

Installing does the following:

1. Copies the build to `%LOCALAPPDATA%\Programs\Web App Wrap`.
2. Adds **Web App Wrap** to the Start menu.
3. Adds that folder to your user PATH, so `waw` works in any new terminal.

To remove it, run `.\scripts\uninstall.ps1`. Add `-RemoveApps` to also remove
every wrapped app, along with its shortcuts and sign-ins.

## Use

1. Open **Web App Wrap** from the Start menu.
2. Enter the app name and the web address.
   - You can leave out `https://`. Addresses that start with `localhost` use
     `http://`.
   - To put the app in a Start menu folder, include the folder in the name:
     `Web App Wrap/Photos` creates **Photos** in a **Web App Wrap** folder.
3. Optionally, drop a square image on the icon or click **Choose Image…**. PNG,
   JPEG, BMP, GIF, WebP and ICO files all work.
   - Web App Wrap draws the image as a rounded square, in the style of Windows
     11 app icons.
   - If the image has a solid-color or transparent border, for example an icon
     that's already rounded on a white square, Web App Wrap zooms in just far
     enough to crop the border out. The slider zooms in further from there.
   - Without an image, Web App Wrap draws a colored tile with the app name's
     first letter.
4. Check the **Title bar color**.
   - After you enter the web address, Web App Wrap fills it in with the site's
     theme color, from its `<meta name="theme-color">` tag or its web app
     manifest.
   - To use a different color, click the color and pick one. **Use Site Color**
     switches back.
   - If the site has no theme color, Web App Wrap uses `#1E1E1E`.
5. Optionally, tick **Also add a shortcut to the desktop**.
6. Click **Create App**. If an app with that name already exists, Web App Wrap
   asks before replacing it.

Recreating an app under the same name keeps its sign-ins. For example, you can
recreate it to change its icon or URL. Sign-ins are tied to the app's ID,
`com.waw.app.<name>`.

Click the **?** button for help with the app and the full command-line
reference.

### Many apps at once (JSON)

Click **Create from JSON…**, then pick a JSON file containing an array of apps.
The format is the same as on macOS:

```json
[
  {
    "name": "Web App Wrap/Photos",
    "url": "https://kphotos.vercel.app",
    "image": "icons\\photos.png",
    "zoom": 1.2,
    "titleBarColor": "#1a1a1a"
  },
  { "name": "Linear", "url": "linear.app" }
]
```

| Field | Required | Meaning |
| --- | --- | --- |
| `name` | yes | App name. It may include Start menu folders, as in the window |
| `url` | yes | Web address |
| `image` | no | Icon image path, relative to the JSON file unless it's a full path (`~` means your user folder). Without it, Web App Wrap draws the default icon |
| `zoom` | no | 1–3, applied on top of the automatic zoom that crops off a border. Defaults to 1 |
| `titleBarColor` | no | For example `"#1a1a1a"`. Defaults to the site's theme color |

The file can also be JSONC or JSON5 (`.jsonc`, `.json5`), so comments, trailing
commas, unquoted keys and single-quoted strings are fine:

```json5
// My apps
[
  { name: 'Linear', url: 'linear.app' }, // work
  { name: 'Photos', url: 'kphotos.vercel.app' },
]
```

Before building, Web App Wrap checks the whole file and lists every problem at
once, such as a missing field, a bad color, an unknown field, or two entries
with the same name. It then shows the apps it's about to create, including any
that already exist and will be replaced. It builds them one at a time. If any
fail, it lists them at the end without stopping the rest.

### Command line

`waw.exe` is installed next to Web App Wrap and is on your PATH after installing.

```powershell
waw build --name "Web App Wrap/Linear" --url linear.app
waw build --name "Grafana" --url localhost:3000 --image ~\grafana.png --zoom 1.2 --title-bar-color "#1a1a1a" --desktop
waw batch apps.json              # every app in a JSON file
waw icon --name "Linear" --out Linear.ico   # just the icon
waw help
```

| Option | Commands | Meaning |
| --- | --- | --- |
| `--name` | build, icon | App name, with optional Start menu folders. Required for `build` |
| `--url` | build | Web address. Required |
| `--image` | build, icon | Icon image |
| `--zoom` | build, icon | 1–3, on top of the automatic border crop |
| `--title-bar-color` | build | Hex color. Default: the site's theme color |
| `--desktop` | build, batch | Also put a shortcut on the desktop |
| `--out` | build, batch, icon | Shortcut folder for `build` and `batch` (default: the Start menu); the `.ico` path for `icon` (required) |

`batch` exits with status 1 if any app failed.

## How it works

A Mac app is a folder, so on macOS each wrapped app gets its own copy of a small
browser shell. That doesn't work well on Windows: a self-contained WinUI program
is large, and its icon is compiled into the `.exe`. So every wrapped app runs
the one installed `WebAppWrap.exe`, the same way Chrome's installed web apps
run `chrome.exe`. A wrapped app is the following:

- **A Start menu shortcut** that runs `WebAppWrap.exe --app com.waw.app.<name>`,
  with the app's icon and its own **AppUserModelID**. Windows groups taskbar
  buttons and pins by that ID, so each wrapped app gets its own taskbar button
  and icon.
- **A data folder** at `%LOCALAPPDATA%\Web App Wrap\Apps\com.waw.app.<name>`
  with these files:
  - `app.json`: name, URL and title-bar color
  - `icon.ico`: every size from 16 to 256 px
  - `window.json`: the last window size and position
  - `WebView2\`: the app's own cookies, storage and sign-ins

Launching a wrapped app that's already open opens another window in the
running process. Each window's title bar is a WinUI `TabView` drawn into the
title-bar area. The tabs and `+` are marked as clickable regions, so dragging a
tab reorders it, and the rest of the bar still moves the window. Each tab is a
WebView2. While a page has focus, WebView2 receives every key press first, so a
small script added to every page passes the tab shortcuts back to the window.

```
src/
  WebAppWrap/        WinUI 3 app: the Web App Wrap window, the help window, and the
                     wrapped-app browser window (built in C#, no XAML files)
  waw/               the command-line tool
  WebAppWrap.Core/   shared logic: URL cleanup, naming, link routing, theme colors,
                     batch files, icon drawing (SkiaSharp), shortcuts
tests/
  WebAppWrap.Core.Tests/
scripts/             build, install and uninstall (PowerShell)
```

### Development

```powershell
dotnet test tests\WebAppWrap.Core.Tests          # works on macOS and Linux too
dotnet run --project src\WebAppWrap -r win-x64   # the Web App Wrap window
dotnet run --project src\waw -- help
```

To try the browser window, run
`WebAppWrap.exe --app com.waw.app.<name>` for an app you've already created.

## Limitations

- Wrapped apps run the installed `WebAppWrap.exe`. If you move or delete Web App
  Wrap, its apps stop launching. Reinstalling to the default location fixes
  them.
- Tabs can't be dragged out into their own window.
- Pages that use the same shortcuts (Ctrl+T, Ctrl+W, Ctrl+N, Ctrl+H, Ctrl+L,
  Ctrl+Tab, Ctrl+1–9) won't receive them.
- An https page can't load anything from an http:// server (mixed content).
  Serve the server over https too.
- Web App Wrap can't intercept Ctrl+click on elements whose navigation is pure
  JavaScript (no real link, just a click handler).
