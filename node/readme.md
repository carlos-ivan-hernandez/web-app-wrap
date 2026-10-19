# Web App Wrap for Node

Opens your web apps as separate native windows with tabs, straight from
`npm start`. You don't build anything or install anything per app.

```bash
npm install
npm start -- apps.json
```

- **Each app gets its own window and its own process.** If one app crashes or
  hangs, the others keep running.
- **It always uses the operating system's own web engine.** That's WebView2
  (Edge) on Windows, WKWebView (Safari) on macOS, and WebKitGTK on Linux.
  Nothing bundles a browser, unlike Electron. The windows come from
  [@webviewjs/webview](https://www.npmjs.com/package/@webviewjs/webview), Node
  bindings for the wry and tao libraries that Tauri uses.
- **Your tabs come back.** While the apps run, and when they close, the open
  windows and tabs are saved next to your config. `apps.json` saves to
  `apps.session.json`. The next `npm start -- apps.json` reopens them.

This is a lighter alternative to the native
[macOS](../macos) and [Windows](../windows) versions of Web App Wrap. Those
create real installed apps; this one runs your apps from a terminal.

## Requirements

- Node.js 24 or later.
- On Linux, the WebKitGTK 4.1 runtime. For example, on Debian or Ubuntu:
  `sudo apt install libwebkit2gtk-4.1-0`.
- WebView2 on Windows and WKWebView on macOS are already part of the OS.

## The config file

The config uses the same JSON format as Web App Wrap's batch files, so one file
works with every version. See [apps.example.json](apps.example.json).

```json
[
  { "name": "Photos", "url": "https://kphotos.vercel.app", "image": "icons/photos.png", "titleBarColor": "#1a1a1a" },
  { "name": "Linear", "url": "linear.app" }
]
```

| Field | Required | Meaning |
| --- | --- | --- |
| `name` | yes | App name. Each app needs a different name. Folders in a name (`"Web App Wrap/Photos"`) are accepted and ignored |
| `url` | yes | Web address. You can leave out `https://`; addresses starting with `localhost` use `http://` |
| `image` | no | A PNG for the window and taskbar icon, relative to the config file |
| `titleBarColor` | no | Tab bar color, for example `"#1a1a1a"`. Defaults to the site's theme color, from its `<meta name="theme-color">` or web app manifest |
| `zoom` | no | Accepted so batch files work, but ignored |

If anything in the file is wrong, `npm start` lists every problem at once and
doesn't open anything.

You can also set the config path in the `WEB_APP_WRAP_CONFIG` environment
variable instead of passing it.

## Saved tabs

- **What's saved:** every open window and its tabs, in order, along with the
  selected tab and each window's size and position. Address changes that
  single-page apps make without reloading are included.
- **When it's saved:**
  - shortly after every change, so even a crash or power loss keeps recent
    tabs
  - whenever an app closes
  - when everything shuts down
- **Closing apps:**
  - Ctrl+C in the terminal closes every app and saves their tabs.
  - Closing an app's last window quits just that app, and its tabs are what
    reopen next time.
  - When the last app closes, `npm start` saves the session and exits.
- **Starting fresh:** to open each app at its address, ignoring saved tabs, run
  `npm start -- apps.json --fresh`. Deleting `apps.session.json` does the same.
- **Removed apps:** if you take an app out of the config, its saved tabs are
  kept in the session file in case you add it back.

## Tabs

The tab bar uses the same style as the other versions:

- It takes the app's title-bar color.
- Thin dividers separate the tabs.
- The selected tab has brighter text.
- It only appears when two or more tabs are open.

| Action | macOS | Windows and Linux |
| --- | --- | --- |
| New tab at the app's address | ⌘T, or `+` | Ctrl+T, or `+` |
| Open a link in a background tab | ⌘-click or middle-click | Ctrl+click or middle-click |
| …and switch to it | ⇧⌘-click | Ctrl+Shift+click |
| Close tab (the last one closes the window) | ⌘W, or × | Ctrl+W, or × |
| Close window | ⇧⌘W | Ctrl+Shift+W |
| New window | ⌘N | Ctrl+N |
| Previous / next tab | ⌘H / ⌘L | Ctrl+H / Ctrl+L, Ctrl+Shift+Tab / Ctrl+Tab |
| Go to tab 1–8 / last tab | ⌘1–⌘8 / ⌘9 | Ctrl+1–Ctrl+8 / Ctrl+9 |
| Reorder tabs | drag a tab | drag a tab |
| Reload, back, forward | ⌘R, ⌘[, ⌘] | F5 or Ctrl+R, Alt+←, Alt+→ |
| Developer tools | ⌥⌘I | F12 or Ctrl+Shift+I |

On macOS, the shortcuts live in the menu bar, which also makes Copy, Paste and
Select All work inside pages. Quit (⌘Q) saves the tabs like closing the
windows does.

**Linux: tabs open as windows.** A window can hold several webviews only as
"child" webviews. On Linux those don't receive keyboard focus, so you couldn't
type into the page. They also need X11, and most Linux desktops now run
Wayland. So on Linux each tab opens as its own window of the app. Ctrl+T,
Ctrl+click, Ctrl+W, Ctrl+H / Ctrl+L (which move between the app's windows) and
saved sessions all work the same way. To try real tabs on Linux anyway, set
`WEB_APP_WRAP_LINUX_TABS=1`.

## Which links stay in the app

The routing works the same way as in the other versions:

- **In the app:** the app's own host and its subdomains (`www.` is ignored).
- **In your default browser:** links to other sites that you click.
- **In the app that handles the link:** `mailto:`, `tel:`, `zoommtg:` and other
  non-web links.

Redirects and script-driven navigation to other sites stay in the app, so
single sign-on (SSO) and OAuth sign-in work. A sign-in popup that a script
opens with a set size, such as "Sign in with Google", opens as a tab in the
app. However, that tab can't send its result back to the page that opened it,
so popup-only sign-ins may not finish. Many sites fall back to a full-page
sign-in, which works.

## How it works

```
npm start -- apps.json
  └─ src/launcher.js        reads the config and the saved session, starts one process per app,
       │                    collects each app's open tabs, writes apps.session.json
       ├─ src/app-process.js  (Photos)   a native window per window, a webview per tab
       └─ src/app-process.js  (Linear)
```

Each app process keeps its cookies, storage and sign-ins in its own folder:

- Windows: `%LOCALAPPDATA%\Web App Wrap\Node\<app>`
- macOS: `~/Library/Application Support/Web App Wrap/Node/<app>`
- Linux: `~/.local/share/web-app-wrap/<app>`

A small script added to every page handles three jobs:

- it sends clicked links to the right place
- it reports address changes in single-page apps, so saved tabs stay current
- on Windows and Linux, it forwards the shortcuts

| File | What it does |
| --- | --- |
| `src/launcher.js` | Entry point; starts the app processes and saves the session |
| `src/app-process.js` | One app: its windows, menu, theme color and reporting |
| `src/app-window.js` | One window: the tab bar, the page webviews, link routing and commands |
| `src/ui.js` | The tab bar page, and the script added to every page |
| `src/config.js`, `src/session.js`, `src/tabs.js`, `src/links.js`, `src/color.js` | Config, session file, tab order, link routing and colors (tested in `test/`) |

```bash
npm test
```

## Limitations

- **macOS identity:** each app runs as a `node` process, so on macOS the Dock
  shows the Node icon and the bold menu-bar name is "node". The app's name is
  still on its own menu and windows.
- **macOS sign-ins:** apps might share cookies and sign-ins, because macOS's
  web engine may ignore the per-app data folder. On Windows and Linux each app
  has its own.
- **Running twice:** running `npm start` twice with the same config opens every
  app twice.
- **Tab bar position:** the tab bar sits below the system's title bar. This
  version can't move tabs into the title bar, because the library has no way to
  drag a window by a custom-drawn bar.
