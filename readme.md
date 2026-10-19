# Web App Wrap

A native macOS app that turns any web app into its own native macOS app, with
real tabs.

Give it a name, a web address, and (optionally) an image. It creates
`<Name>.app` with a full set of macOS icon sizes, its own Dock icon, and its own
cookies and storage.

## Tabs in generated apps

The window has a single bar at the top, in the title-bar color you pick in
Web App Wrap, with the close, minimize and zoom buttons on the left. With one tab
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
- To build: Xcode or the Xcode command line tools (`xcode-select --install`).
  Building needs Swift 5.9 or later.

Generated apps need nothing extra. Each one includes everything it needs.

## Build

```bash
./scripts/build.sh            # creates "dist/Web App Wrap.app"
./scripts/build.sh --install  # also copies it into /Applications
UNIVERSAL=1 ./scripts/build.sh  # Apple silicon + Intel (needs full Xcode)
```

## Use

1. Open Web App Wrap.
2. Enter the app name and the web address. To save the app in a subfolder of
   Applications, put the folder in the name: `Web App Wrap/Photos` creates
   `/Applications/Web App Wrap/Photos.app`, and the app is named "Photos". You can leave out `https://`.
   Addresses that start with `localhost` use `http://`.
3. Optionally, drop a square image on the icon area or click **Choose Image…**.
   PNG, JPEG, HEIC, PDF and ICNS files all work. Web App Wrap rounds the corners to
   the macOS icon shape and adds the standard margin and shadow. If you want to
   crop in, drag the zoom slider under the preview. If the image has a solid-color
   or transparent border, for example an icon that's already rounded on a white
   square, Web App Wrap zooms in just far enough to crop the border out. That zoom is the
   starting point, and the slider only zooms in further from there. Without an image, Web App Wrap
   draws a colored tile with the app name's first letter.
4. Check the **Title bar color**. It's the background of the bar holding the
   window buttons and tabs. After you enter the web address, Web App Wrap fills it in
   with the site's theme color, from its `<meta name="theme-color">` tag or its
   web app manifest. You can pick a different color, and **Use Site Color**
   switches back. If the site has no theme color, Web App Wrap uses `#1E1E1E`. The text
   switches between light and dark to stay readable.
5. Click **Create App**. Web App Wrap saves the app in `/Applications`. If an app with
   that name is already there, Web App Wrap asks before replacing it and moves the old
   copy to the Trash.

You can recreate an app under the same name, for example to change its icon or
URL. It keeps its sign-ins, because the app's data is tied to its bundle ID
(`com.waw.app.<name>`).

Choose **Help → Web App Wrap Help**, or click the **?** in the window, for
a guide to the app and the full command-line reference.

### Many apps at once (JSON)

Choose **File → Create Apps from JSON…** (⇧⌘O) or click **Create from JSON…**.
Then pick a JSON file containing an array of apps. Each app takes the same
inputs as the window:

```json
[
  {
    "name": "Web App Wrap/Photos",
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
| `image` | no | Icon image path, relative to the JSON file unless absolute (`~` works). Without it, Web App Wrap draws the default icon |
| `zoom` | no | 1–3, applied on top of the automatic zoom that crops off a border. Defaults to 1 |
| `titleBarColor` | no | For example `"#1a1a1a"`. Defaults to the site's theme color |

Before building, Web App Wrap checks the whole file and lists every problem at once,
such as a missing field, a bad color, an unknown field or two entries with the
same name. It then shows the apps it's about to create, including any that
already exist and will be replaced. It builds them one at a time, and if any
fail, it lists them at the end without stopping the rest.

### Command line

```bash
wrap="/Applications/Web App Wrap.app/Contents/MacOS/WebAppWrap"
"$wrap" build --name "Web App Wrap/Linear" --url linear.app
"$wrap" build --name "Grafana" --url localhost:3000 --image ~/grafana.png --zoom 1.2 --title-bar-color "#1a1a1a" --out ~/Applications
"$wrap" batch ~/apps.json                      # every app in a JSON file
"$wrap" icon --name "Linear" --out Linear.icns # just the icon
```

## How it works

Web App Wrap.app contains a prebuilt browser shell (`WebAppWrapRuntime`). To create an
app, Web App Wrap does the following:

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

```
Sources/
  WebAppWrap/       the generator app (SwiftUI) and its command line
  WebAppWrapRuntime/   the browser shell copied into every generated app (AppKit + WKWebView)
  WebAppWrapKit/       shared logic: URL normalization, naming, link routing
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
- Windows are moved by dragging the bar's background with Web App Wrap's own drag
  handling (needed so dragging a tab doesn't move the window). Dragging a window
  to a screen edge to tile it therefore doesn't work; use the green button's
  tiling options or the Window menu instead.
- ⌘H switches tabs instead of hiding the app. **Hide** is still in the app menu,
  and ⌥⌘H still hides other apps.
- Web App Wrap can't intercept ⌘-click on elements whose navigation is pure
  JavaScript (no real link, just a click handler).
