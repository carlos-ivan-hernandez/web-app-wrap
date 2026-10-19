# WebWrap

A native macOS app that turns any web app into its own native macOS app, with
real tabs.

Give it a name, a web address, and (optionally) an image. It creates
`<Name>.app` with a full set of macOS icon sizes, its own Dock icon, and its own
cookies and storage.

## Tabs in generated apps

The tabs sit in the title bar, in line with the close, minimize and zoom
buttons, so there's no separate title-bar row. The tab strip takes its color from
the page (its `theme-color`, or else its background color), so it blends into
the web app.

| Action | Result |
| --- | --- |
| ⌘T, or the `+` after the tabs | New tab at the base URL |
| ⌘-click a link | Opens in a new background tab |
| ⇧⌘-click a link | Opens in a new tab and switches to it |
| ⌘W, or the tab's × (middle-click also works) | Closes the tab. Closing the last tab quits the app |
| ⇧⌘W | Closes the window and all its tabs |
| ⌘N | New window |
| ⌘1 … ⌘8, ⌘9 | Go to tab N, or to the last tab |
| ⌃⇥ / ⌃⇧⇥, or ⇧⌘] / ⇧⌘[ | Next / previous tab |
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

## Requirements

- macOS 13 Ventura or later
- To build: Xcode or the Xcode command line tools (`xcode-select --install`).
  Building needs Swift 5.9 or later.

Generated apps need nothing extra. Each one includes everything it needs.

## Build

```bash
./scripts/build.sh            # creates dist/WebWrap.app
./scripts/build.sh --install  # also copies it into /Applications
UNIVERSAL=1 ./scripts/build.sh  # Apple silicon + Intel (needs full Xcode)
```

## Use

1. Open WebWrap.
2. Enter the app name and the web address. You can leave out `https://`.
   Addresses that start with `localhost` use `http://`.
3. Optionally, drop an image on the icon area or click **Choose Image…**. PNG,
   JPEG, HEIC, PDF and ICNS files all work. Without an image, WebWrap draws a
   colored tile with the app name's first letter.
4. If you added an image, pick an **Icon style**:
   - **Fill:** crops the image to fill the rounded square. Use this for photos
     and square logos. It's the default for images with no transparency.
   - **Fit on White:** places the image on a white rounded square. Use this
     for logos on a transparent background. It's the default for those.
   - **As Is:** uses the image unchanged. Use this for an image that's already a
     finished macOS icon.
5. Click **Create App…** and choose where to save. The default is
   `/Applications`. If an app with that name already exists there, WebWrap
   moves the old copy to the Trash.

You can recreate an app under the same name, for example to change its icon or
URL. It keeps its sign-ins, because the app's data is tied to its bundle ID
(`com.webwrap.app.<name>`).

### Command line

```bash
WebWrap=/Applications/WebWrap.app/Contents/MacOS/WebWrap
$WebWrap build --name "Linear" --url linear.app
$WebWrap build --name "Grafana" --url localhost:3000 --image ~/grafana.png --style fit --out ~/Applications
$WebWrap icon --name "Linear" --out Linear.icns   # just the icon
```

## How it works

WebWrap.app contains a prebuilt browser shell (`WebWrapRuntime`). To create an
app, WebWrap does the following:

1. Copies the shell into a new `.app` bundle.
2. Writes an `Info.plist` with the name, the bundle ID, and the base URL (the
   `WebWrapBaseURL` key).
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
  WebWrap/          the generator app (SwiftUI) and its command line
  WebWrapRuntime/   the browser shell copied into every generated app (AppKit + WKWebView)
  WebWrapKit/       shared logic: URL normalization, naming, link routing
Tests/
  WebWrapKitTests/
```

### Development

```bash
swift test                                         # tests for the shared logic
swift run WebWrap                                  # the generator, without bundling
swift run WebWrapRuntime --url https://example.com # the browser shell, pointed at any URL
```

## Limitations

- Generated apps are signed ad hoc, not notarized. They run on the Mac that
  created them. To run one on another Mac, right-click it and choose **Open**
  the first time.
- Tabs can't be reordered by dragging, or dragged out into their own window.
- WebWrap can't intercept ⌘-click on elements whose navigation is pure
  JavaScript (no real link, just a click handler).
