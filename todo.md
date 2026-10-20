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

On macOS, the code to follow is:

- `macos/Sources/WebAppWrapKit/AppRecord.swift` and `AppRegistry.swift`: the
  list format, skip rules and icon storage
- `macos/Sources/WebAppWrap/BuilderModel.swift`, `AppListView.swift`
- `macos/scripts/build.sh`: stamping the commit
- `macos/Sources/WebAppWrapKit/ExtensionStore.swift`, `ExtensionManifest.swift`,
  `macos/Sources/WebAppWrap/ExtensionsModel.swift`, `ExtensionsView.swift`, and
  `macos/Sources/WebAppWrapRuntime/ExtensionHost.swift`, `ExtensionSupport.swift`

Keep `apps.json` and `extensions.json` in the same format on both platforms.
