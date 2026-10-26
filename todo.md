# To do

## Windows: catch up with the macOS app list and rename

The macOS version got these changes. The Windows version (`windows/`) doesn't
have them yet:

- [ ] **Rename the app to WebAppWrap** (no spaces): window titles, Start menu
      entry, install folder, help text, readme. Check what the rename means for
      the existing data folder (`%LOCALAPPDATA%\Web App Wrap\Apps`) and for apps
      already installed.
- [ ] **Remove the "Create from JSON" button** (and any menu item for it). Keep
      the `waw batch` command.
- [ ] **One-Off / My Apps modes** in the generator window. One-Off works as the
      window does now, and also records the app in the list. My Apps lists every
      app made in the window and lets you add, edit and remove apps, then build
      them all.
- [ ] **Skip unchanged apps.** An app is skipped when its settings match its last
      build and it was built by the same WebAppWrap version. It's rebuilt if it's
      missing. A WebAppWrap build with no version rebuilds everything.
- [ ] **Version = git commit.** Stamp `git rev-parse HEAD` (plus `-dirty` for
      uncommitted changes) into the build from `scripts/build.ps1`, for example
      as an MSBuild property feeding `AssemblyMetadata` or
      `InformationalVersion`. Show it in the window and help, and write it into
      each generated app's `app.json`.
- [ ] **Store the list and icons** in the app's own data folder:
      `apps.json`, `icons/` (a copy of each app's source image) and
      `previous-icons/` (replaced or removed icons, named after the app and the
      time).
- [ ] **Shared browser extensions.** Install once in WebAppWrap (import from
      Chromium browsers, or a folder, .zip or .crx), on for all apps by
      default with per-app overrides, kept in `extensions.json` and
      `extensions/` next to `apps.json`. Wrapped apps read the list at launch
      and when activated. WebView2 can load unpacked extensions
      (`CoreWebView2Profile.AddBrowserExtensionAsync`, with
      `AreBrowserExtensionsEnabled`), but it has no toolbar or popups and less
      API coverage, so per-tab and window APIs and toolbar buttons may not be
      possible. Stamp each app's list ID into its `app.json`.
- [ ] **Extensions menu.** Put extensions behind one title-bar button (a grid
      of four squares, not a puzzle piece) instead of a row of buttons.
- [ ] **More (⋮) menu** at the right of the title bar, with **Open Link…**
      (Ctrl+Shift+L; prefilled from the clipboard, opens in a new or the
      current tab), a **History** submenu of recent pages, **Show All History**
      (Ctrl+H) and the page commands. Keep each app's history in its own
      `history.json`, in the same format as macOS (`BrowsingHistory.swift`).
- [ ] **Allowed Sites** in the ⋮ menu: other domains (with subdomains) that
      count as part of the app, for clicked links, Open Link and history. Open
      Link refuses other sites and offers to allow them. See
      `LinkPolicy.allowedDomains` and `WebAppWrapRuntime/AllowedSites.swift`.
      Include the **Allow All Sites** switch and the list of sites visited
      while it's on, which can be saved to the list.
- [ ] **Apps folder setting.** Let the user pick the folder apps are saved in
      (default: today's install folder), offer to move already-built apps when
      it changes, and use it as `waw`'s default `--out`.
- [ ] **Downloads that can't be saved** to Downloads ask where to save instead
      of failing.
- [ ] **Notifications**: show the site's web notifications as Windows
      notifications, with a ⋮ → Notifications switch, and bring the tab forward
      when one is clicked. WebView2 has `CoreWebView2.NotificationReceived`
      (WebView2 1.0.2420+); on macOS a page script stands in for the API.
- [ ] **Profiles**: separate logins and site data per window (⋮ → Profile, New
      Profile…, Manage Profiles…), with the profile name in the title bar once
      there's more than one. WebView2 profiles: `CoreWebView2ControllerOptions.ProfileName`.
- [ ] **Keyboard Shortcuts…** in the ⋮ menu: change any command's shortcut,
      stored per app.
- [ ] **SVG icons.** The window takes an SVG instead of an image, drawn on a
      background color the user picks (default #1C1C1C) with a zoom slider from
      0.5 to 3 (1 fits the whole SVG). Batch files get `iconBackground` and
      `waw` gets `--icon-background`. Other images keep working as before for
      batch files and the command line. SkiaSharp can't read SVG; the
      `Svg.Skia` package can. See `IconSource.svg` and `IconSource.load` in
      `macos/Sources/WebAppWrap/IconRenderer.swift`, and `AppDraft.swift`.
- [ ] **Reopen Tabs at Launch** in the ⋮ menu (on by default): save each
      window's tabs, selected tab, profile and position to `tabs.json` next to
      `history.json` a second after each change and when the last window
      closes, and reopen them at launch, skipping sites no longer allowed. See
      `macos/Sources/WebAppWrapKit/SavedTabs.swift` and the "Reopening tabs"
      part of `WebAppWrapRuntime/AppDelegate.swift`.

On macOS, the code to follow is:

- `macos/Sources/WebAppWrapKit/AppRecord.swift` and `AppRegistry.swift`: the
  list format, skip rules and icon storage
- `macos/Sources/WebAppWrap/BuilderModel.swift`, `AppListView.swift`
- `macos/scripts/build.sh`: stamping the commit
- `macos/Sources/WebAppWrapKit/BrowsingHistory.swift` and
  `macos/Sources/WebAppWrapRuntime/History.swift`: history; the ⋮ and
  Extensions menus are in `BrowserWindowController.swift`
- `macos/Sources/WebAppWrap/AppsFolder.swift` and `BuilderModel.setAppsFolder`:
  the apps folder
- `macos/Sources/WebAppWrapRuntime/DownloadManager.swift`, `NotificationBridge.swift`,
  `Profiles.swift`, `Shortcuts.swift` and `ShortcutsWindow.swift`
- `macos/Sources/WebAppWrapKit/ExtensionStore.swift`, `ExtensionManifest.swift`,
  `macos/Sources/WebAppWrap/ExtensionsModel.swift`, `ExtensionsView.swift`, and
  `macos/Sources/WebAppWrapRuntime/ExtensionHost.swift`, `ExtensionSupport.swift`

Keep `apps.json` and `extensions.json` in the same format on both platforms.
