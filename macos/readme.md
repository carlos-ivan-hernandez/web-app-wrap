# WebAppWrap for macOS

A native macOS app that turns any web app into its own native macOS app, with
real tabs.

Give it a name, a web address, and (optionally) an image. It creates
`<Name>.app` with a full set of macOS icon sizes, its own Dock icon, and its own
cookies and storage.

This is the macOS version. The Windows version is in [../windows](../windows).
Run the commands below from this `macos` folder.

## Tabs in generated apps

The window has a single bar at the top, in the title-bar color you pick in
WebAppWrap, with the close, minimize and zoom buttons on the left. With one tab
open, that's all it shows. With two or more, tabs up to 240pt wide sit side by
side, separated by thin dividers, and shrink to fit when there are many. Every
tab uses the bar's color. The
selected tab is marked by brighter text and its close button.

| Action | Result |
| --- | --- |
| ⌘T, or the `+` after the last tab | New tab at the base URL |
| ⌘-click a link | Opens in a new background tab |
| ⇧⌘-click a link | Opens in a new tab and switches to it |
| ⌘W, or the tab's × (middle-click also works) | Closes the tab. Closing the last tab quits the app |
| ⇧⌘W | Closes the window and all its tabs |
| ⌘N | New window |
| ⌘1 … ⌘8, ⌘9 | Go to tab N, or to the last tab |
| ⌘H / ⌘L | Previous / next tab (⌃⇧⇥ / ⌃⇥ and ⇧⌘[ / ⇧⌘] also work) |
| Drag a tab sideways | Reorder tabs |
| ⌘[ / ⌘] | Back / forward (two-finger swipe also works) |
| ⇧⌘H | Go to the base URL |
| ⌘R | Reload |
| ⌘+ / ⌘- / ⌘0 | Zoom in, zoom out, actual size |
| ⇧⌘C | Copy the page's link |
| ⇧⌘O | Open the page in your default browser |
| ⌥⌘I, or right-click → Inspect Element | Web Inspector (console, network, elements) |
| ⌥⌘R | Reload, bypassing the cache |

### Which links stay in the app

- **In the app:** the base URL's host and its subdomains (`www.` is ignored).
  With a base of `app.example.com`, `eu.app.example.com` also counts.
- **In your default browser:** any clicked link to a different host.
- **In the app that handles the link:** `mailto:`, `tel:`, `zoommtg:` and other
  non-web links.

Redirects and script-driven navigation to other hosts stay in the app. Clicked
links to those hosts don't. This keeps single sign-on (SSO) and OAuth sign-in
working. Sign-in popups opened by a script (for example "Sign in with Google")
also open in a tab inside the app, so they can report back to the page that
opened them.

Downloads go to `~/Downloads`. File uploads, JavaScript alerts, and camera and
microphone access work. If a page fails to load, the app shows an error page
with a **Try Again** button.

Source code and issues: https://github.com/carlos-ivan-hernandez/web-app-wrap

## Requirements

- macOS 13 Ventura or later
- To build: Xcode or the Xcode command line tools (`xcode-select --install`),
  with Swift 5.9 or later. Extension support needs Xcode 16.3 or later (Swift
  6.1 and the macOS 15.4 SDK). With an older Xcode, WebAppWrap builds without
  it, and the apps' Extensions menu says so.
- Extensions in generated apps need macOS 15.4 or later. On older systems the
  apps work as before, without extensions.

Generated apps need nothing extra. Each one includes everything it needs.

## Build

```bash
./scripts/build.sh            # creates dist/WebAppWrap.app, versioned with the current commit
./scripts/build.sh --install  # also copies it into /Applications
UNIVERSAL=1 ./scripts/build.sh  # Apple silicon + Intel (needs full Xcode)
```

## Use

WebAppWrap has two modes, picked at the top of its window: **One-Off** makes a
single app right now, and **My Apps** keeps a list of your apps and builds them.

### One-Off

1. Choose **One-Off** at the top of the window.
2. Enter the app name and the web address. To save the app in a subfolder of
   Applications, put the folder in the name: `WebAppWrap/Photos` creates
   `/Applications/WebAppWrap/Photos.app`, and the app is named "Photos". You can leave out `https://`.
   Addresses that start with `localhost` use `http://`.
3. Optionally, drop a square image on the icon area or click **Choose Image…**.
   PNG, JPEG, HEIC, PDF and ICNS files all work. WebAppWrap rounds the corners to
   the macOS icon shape and adds the standard margin and shadow. If you want to
   crop in, drag the zoom slider under the preview. If the image has a solid-color
   or transparent border, for example an icon that's already rounded on a white
   square, WebAppWrap zooms in just far enough to crop the border out. That zoom is the
   starting point, and the slider only zooms in further from there. Without an image, WebAppWrap
   draws a colored tile with the app name's first letter.
4. Check the **Title bar color**. It's the background of the bar holding the
   window buttons and tabs. After you enter the web address, WebAppWrap fills it in
   with the site's theme color, from its `<meta name="theme-color">` tag or its
   web app manifest. You can pick a different color, and **Use Site Color**
   switches back. If the site has no theme color, WebAppWrap uses `#1C1C1C`. The text
   switches between light and dark to stay readable.
5. Click **Create App**. WebAppWrap saves the app in `/Applications`. If an app with
   that name is already there, WebAppWrap asks before replacing it and moves the old
   copy to the Trash.

The app is also added to **My Apps**, or updates the entry there with the same
name.

You can recreate an app under the same name, for example to change its icon or
URL. It keeps its sign-ins, because the app's data is tied to its bundle ID
(`com.waw.app.<name>`).

### My Apps

**My Apps** lists every app made in the window, with its icon, address and
whether it's up to date. The window opens in this mode once the list has any
apps in it.

- **+** adds an app, using the same fields as One-Off. Adding doesn't build it.
- Double-click an app, or select it and click **Edit…**, to change it.
- **−** (or Delete) takes an app off the list. The app itself stays installed.
- Right-click an app to build just that one, open it, or show it in Finder.
- **Build Apps** opens a page listing every app that needs building, why
  (for example, its settings changed), and whether it creates a new app or
  replaces one in Applications. Nothing is built until you click **Build**
  there; **Back** returns to the list. Each app's progress and result show on
  the same page, and **Done** returns to the list.

An app is **skipped** when both of these are true:

- Nothing about it (name, address, icon, zoom or title bar color) has changed
  since it was last built.
- It was last built by this version of WebAppWrap.

It's also rebuilt if it's no longer in Applications. So after you update
WebAppWrap, **Build Apps** rebuilds all your apps with the new version.

WebAppWrap's version is the git commit it was built from. `scripts/build.sh`
writes it into WebAppWrap's `Info.plist` (the `WebAppWrapCommit` key), with
`-dirty` added if the checkout had uncommitted changes. The window shows it at
the bottom of My Apps and in Help. Each app WebAppWrap creates gets the same key
in its own `Info.plist`, so you can see which version built it. A WebAppWrap with
no version (run with `swift run`, or built outside a git checkout) rebuilds
every app every time.

#### Where the list and icons are kept

WebAppWrap keeps its files in `~/Library/Application Support/WebAppWrap`:

| Path | What it holds |
| --- | --- |
| `apps.json` | Every app's settings, and when, from which settings, and by which WebAppWrap version it was last built |
| `icons/` | A copy of each app's icon image, so you don't need the original file again |
| `previous-icons/` | Icons that were replaced, or whose app was removed from the list, named after the app and the time |

Renaming an app in the list doesn't remove the app built under the old name.

### Extensions

Install a browser extension once, and every app WebAppWrap creates can use it.
Generated apps load extensions with WebKit's web extension support, which reads
the same format as Chrome, so most Chrome extensions work. Extensions need
macOS 15.4 or later.

1. Choose **Extensions** at the top of the window.
2. Click **+**, then either:
   - **Import from Chrome or Another Browser…** lists the extensions installed
     in Chrome, Chromium, Brave, Edge, Helium, Vivaldi, Arc, Dia, Comet,
     Opera, Yandex and Thorium (and the beta, dev, canary and nightly
     versions of Chrome, Brave, Edge and Vivaldi). Pick the ones you want.
     The **Browsers** menu at the top chooses which browsers' extensions are
     listed, and WebAppWrap remembers your choice.
   - **Add from File or Folder…** takes an unpacked extension folder (with a
     `manifest.json`), a `.zip` or a `.crx`.
3. WebAppWrap shows what each extension can access and warns about anything
   WebKit doesn't support. Installing grants those permissions.

A new extension is on for all apps. To change that, double-click it (or click
**Choose Apps…**): turn the default off, or turn it on or off for individual
apps. An app's **Edit** sheet in My Apps has the same switches.

Each app also has an **Extensions** menu. There you can turn an extension on or
off for that app, click its toolbar button, or open its options. Extension
buttons appear at the right end of the tab bar, and their popups open under
them.

Changes never need a rebuild. A running app loads and unloads extensions the
next time you switch to it. Installing a newer version (importing again, or
adding a file with the same extension name) updates it everywhere and keeps
each app's settings.

What to expect:

- Each app runs its own copy of each extension, with its own settings and
  storage. Settings from your browser don't carry over, and setting up an
  extension in one app doesn't change it in the others.
- Extensions that need things WebKit doesn't have won't fully work. That
  includes password managers that talk to their desktop app (native
  messaging), Chrome sign-in (`identity`), and request blocking with
  `webRequestBlocking`. Use **uBlock Origin Lite** rather than uBlock Origin.
- Keyboard shortcuts declared in an extension's manifest, side panels and
  extension items in the right-click menu aren't supported yet.
- Apps made from the command line have no ID in the list, so they always use
  each extension's default.

Extensions are kept with the list, in
`~/Library/Application Support/WebAppWrap`:

| Path | What it holds |
| --- | --- |
| `extensions.json` | Installed extensions, each one's default, and apps that differ from it |
| `extensions/<id>/<version>/` | Each extension's files. The previous version is kept until the next update |

Each app has an ID in the list, written into its `Info.plist` as
`WebAppWrapAppID`. That's how it finds its own settings in `extensions.json`.

Choose **Help → WebAppWrap Help**, or click the **?** in the window, for
a guide to the app and the full command-line reference.

### Many apps at once from the command line (JSON)

The `batch` command builds every app in a JSON file. Apps built from the
command line aren't added to My Apps. Each app in the file takes the same
inputs as the window:

```json
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
```

| Field | Required | Meaning |
| --- | --- | --- |
| `name` | yes | App name. It may include folders under Applications, as in the window |
| `url` | yes | Web address |
| `image` | no | Icon image path, relative to the JSON file unless absolute (`~` works). Without it, WebAppWrap draws the default icon |
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

Before building, WebAppWrap checks the whole file and lists every problem at once,
such as a missing field, a bad color, an unknown field or two entries with the
same name. It builds the apps one at a time, and if any fail, it lists them at
the end without stopping the rest.

### Command line

```bash
wrap="/Applications/WebAppWrap.app/Contents/MacOS/WebAppWrap"
"$wrap" build --name "WebAppWrap/Linear" --url linear.app
"$wrap" build --name "Grafana" --url localhost:3000 --image ~/grafana.png --zoom 1.2 --title-bar-color "#1a1a1a" --out ~/Applications
"$wrap" batch ~/apps.json                      # every app in a JSON file
"$wrap" icon --name "Linear" --out Linear.icns # just the icon
```

## How it works

WebAppWrap.app contains a prebuilt browser shell (`WebAppWrapRuntime`). To create an
app, WebAppWrap does the following:

1. Copies the shell into a new `.app` bundle.
2. Writes an `Info.plist` with the name, the bundle ID, and the base URL (the
   `WebAppWrapBaseURL` key).
3. Draws the icon at every size from 16 px to 1024 px (1x and 2x) on Apple's
   icon grid and packs the sizes into `AppIcon.icns` with `iconutil`.
4. Signs the bundle with an ad-hoc signature (`codesign -s -`).

Each window hides its title bar and draws its own tab strip in that space. It
moves the close, minimize and zoom buttons down so they're centered in the strip.
Each tab is a `WKWebView`, and only the selected one is shown in the window.
Dragging empty space in the strip moves the window. Double-clicking it zooms or
minimizes the window, following your System Settings.

Extensions are loaded by `ExtensionHost` with `WKWebExtensionController`.
Tabs and windows adopt `WKWebExtensionTab` and `WKWebExtensionWindow`, so
extension APIs such as `tabs.query` and `windows.getCurrent` see the app's real
tabs.

```
Sources/
  WebAppWrap/       the generator app (SwiftUI) and its command line
  WebAppWrapRuntime/   the browser shell copied into every generated app (AppKit + WKWebView)
  WebAppWrapKit/       shared logic: URL normalization, naming, link routing, the app and extension lists
Tests/
  WebAppWrapKitTests/
```

### Development

```bash
swift test                                         # tests for the shared logic
swift run WebAppWrap                               # the generator, without bundling
swift run WebAppWrapRuntime --url https://example.com # the browser shell, pointed at any URL
```

## Limitations

- Generated apps are signed ad hoc, not notarized. They run on the Mac that
  created them. To run one on another Mac, right-click it and choose **Open**
  the first time.
- Tabs can't be dragged out into their own window.
- Windows are moved by dragging the bar's background with WebAppWrap's own drag
  handling (needed so dragging a tab doesn't move the window). Dragging a window
  to a screen edge to tile it therefore doesn't work; use the green button's
  tiling options or the Window menu instead.
- ⌘H switches tabs instead of hiding the app. **Hide** is still in the app menu,
  and ⌥⌘H still hides other apps.
- WebAppWrap can't intercept ⌘-click on elements whose navigation is pure
  JavaScript (no real link, just a click handler).
