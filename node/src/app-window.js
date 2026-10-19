// One window of a wrapped app: a tab bar webview on top (shown with two or more tabs) and one
// webview per tab below it, all using the system's web engine. On Linux each tab is its own
// window instead (see TABS_SUPPORTED).

import { Theme } from '@webviewjs/webview';
import { isDark } from './color.js';
import { TabList } from './tabs.js';
import { openExternally } from './system.js';
import { pageScript, tabBarHtml } from './ui.js';

const TAB_BAR_HEIGHT = 36;
const DEFAULT_WIDTH = 1280;
const DEFAULT_HEIGHT = 860;
const handleShortcuts = process.platform !== 'darwin';   // macOS uses the app menu instead

/**
 * Tabs need several webviews in one window ("child" webviews). On Linux those don't receive
 * keyboard focus (and need X11), so there each tab opens as its own window of the app instead.
 * WEB_APP_WRAP_LINUX_TABS=1 turns real tabs back on to try them.
 */
export const TABS_SUPPORTED = process.platform !== 'linux' || process.env.WEB_APP_WRAP_LINUX_TABS === '1';

let nextTabNumber = 0;

export class AppWindow {
  /**
   * @param {import('./app-process.js').AppHost} host
   * @param {import('./session.js').WindowState} state tabs to open, and the saved size/position
   * @param {{ cascade?: number, from?: AppWindow }} placement
   */
  constructor(host, state, placement = {}) {
    this.host = host;
    this.tabList = new TabList();
    /** @type {Map<string, { webview: any, url: string, title: string, loading: boolean }>} */
    this.tabs = new Map();
    this.closed = false;
    this.tabBarReady = false;

    const bounds = state.bounds ?? this.defaultBounds(placement);
    this.window = host.app.createBrowserWindow({
      title: host.config.name,
      logical: true,
      width: bounds.width,
      height: bounds.height,
      ...(bounds.x !== undefined ? { x: bounds.x, y: bounds.y } : {}),
    });
    this.window.setMinSize(480, 320, true);
    if (host.icon) {
      this.window.setWindowIcon(host.icon.data, host.icon.width, host.icon.height);
      if (process.platform === 'win32') this.window.setTaskbarIcon(host.icon.data, host.icon.width, host.icon.height);
    }
    if (bounds.x === undefined) this.cascade(placement.cascade ?? 0, bounds);

    this.window.setTheme(isDark(host.titleBarColor) ? Theme.Dark : Theme.Light);
    if (TABS_SUPPORTED) this.createTabBar();
    state.tabs.forEach((tab, index) => this.openTab(tab.url, { activate: index === state.selected, title: tab.title }));

    this.window.on('resize', () => {
      this.layout();
      host.stateChanged();
    });
    this.window.on('move', () => host.stateChanged());
    // The tabs are captured right away, before the views go; the rest happens after the callback.
    this.window.on('close', () => this.onClosed());
  }

  get id() {
    return this.window.id();
  }

  // ---- Layout ----

  defaultBounds({ from }) {
    if (from && !from.closed) {
      const position = from.window.getPosition(true);
      const size = from.window.getInnerSize(true);
      return { x: position.x + 32, y: position.y + 32, width: size.width, height: size.height };
    }
    return { width: DEFAULT_WIDTH, height: DEFAULT_HEIGHT };
  }

  /**
   * Centers a window that has no saved position, shrunk to fit the screen and offset a little per
   * app so they don't stack exactly. (The native size isn't readable yet, so the requested one is used.)
   */
  cascade(step, requested) {
    const monitor = this.window.getPrimaryMonitor() ?? this.window.getCurrentMonitor();
    if (!monitor) return;
    const scale = monitor.scaleFactor || 1;
    const screen = { x: monitor.position.x / scale, y: monitor.position.y / scale, width: monitor.size.width / scale, height: monitor.size.height / scale };
    const width = Math.round(Math.min(requested.width, screen.width * 0.85));
    const height = Math.round(Math.min(requested.height, screen.height * 0.85));
    if (width !== requested.width || height !== requested.height) this.window.setSize(width, height, true);
    const spread = Math.min(8, Math.floor(Math.min(screen.width - width, screen.height - height) / 32) || 1);
    const offset = (step % spread) * 32;
    this.window.setPosition(
      Math.round(screen.x + Math.max(0, (screen.width - width) / 2 - 64) + offset),
      Math.round(screen.y + Math.max(24, (screen.height - height) / 2 - 64) + offset),
      true,
    );
  }

  /** Tabs only show once there are two or more; with one tab the page fills the window. */
  layout() {
    if (this.closed || !TABS_SUPPORTED) return;   // a lone full-window webview resizes by itself
    const { width, height } = this.window.getInnerSize(true);
    const showBar = this.tabList.count > 1;
    const top = showBar ? TAB_BAR_HEIGHT : 0;
    this.tabBar.setWebviewVisibility(showBar);
    if (showBar) this.tabBar.setBounds({ x: 0, y: 0, width, height: TAB_BAR_HEIGHT });
    for (const [id, tab] of this.tabs) {
      tab.webview.setBounds({ x: 0, y: top, width, height: Math.max(0, height - top) });
      tab.webview.setWebviewVisibility(id === this.tabList.selectedId);
    }
  }

  // ---- Tab bar ----

  createTabBar() {
    const { width } = this.window.getInnerSize(true);
    // Loaded as inline HTML. (A window-level custom protocol would also be registered on every
    // tab's webview, and the second one sharing the app's web context fails as a duplicate.)
    this.tabBar = this.window.createWebview({
      child: true,
      html: this.tabBarPage(),
      x: 0, y: 0, width, height: TAB_BAR_HEIGHT,
      enableDevtools: false,
    });
    this.tabBar.setWebviewVisibility(false);
    this.tabBar.onIpcMessage(deferred((message) => this.onTabBarMessage(parse(message))));
  }

  tabBarPage() {
    const color = this.host.titleBarColor;
    return tabBarHtml({ background: color, dark: isDark(color), handleShortcuts });
  }

  renderTabBar() {
    if (this.closed || !this.tabBarReady || !TABS_SUPPORTED) return;
    const state = {
      selected: this.tabList.selectedIndex,
      tabs: this.tabList.ids.map((id) => {
        const tab = this.tabs.get(id);
        return { title: tab.title, loading: tab.loading };
      }),
    };
    this.tabBar.evaluateScript(`window.render && window.render(${JSON.stringify(state)})`);
  }

  onTabBarMessage(message) {
    if (!message) return;
    const idAt = (index) => this.tabList.ids[index];
    switch (message.type) {
      case 'ready':
        this.tabBarReady = true;
        this.renderTabBar();
        break;
      case 'select':
        if (idAt(message.index)) this.selectTab(idAt(message.index));
        break;
      case 'close':
        if (idAt(message.index)) this.closeTab(idAt(message.index));
        break;
      case 'move':
        this.tabList.move(message.from, message.to);
        this.tabsChanged();
        break;
      case 'new-tab':
        this.runCommand('newTab');
        break;
      case 'command':
        this.runCommand(message.command);
        break;
    }
  }

  /** Recolors the tab bar and window chrome once the site's theme color arrives. */
  applyColor(color) {
    if (this.closed) return;
    this.window.setTheme(isDark(color) ? Theme.Dark : Theme.Light);
    if (!TABS_SUPPORTED) return;
    this.tabBarReady = false;
    this.tabBar.loadHtml(this.tabBarPage());
  }

  // ---- Tabs ----

  /**
   * Adds a tab. Link-opened tabs go right after their opener; others go at the end.
   * Without tab support (Linux), a second tab opens as a new window instead.
   */
  openTab(url, { after = null, activate = true, title = '' } = {}) {
    if (!TABS_SUPPORTED && this.tabs.size > 0) {
      this.host.openWindow({ tabs: [{ url, title }], selected: 0 }, { from: this, activate });
      return null;
    }
    const id = `tab${++nextTabNumber}`;
    const { width, height } = this.window.getInnerSize(true);
    const webview = this.window.createWebview({
      ...(TABS_SUPPORTED ? { child: true, x: 0, y: 0, width, height } : { child: false }),
      url,
      enableDevtools: true,
      hotkeysZoom: true,
      clipboard: true,
      autoplay: true,
      backForwardNavigationGestures: true,
      preload: pageScript({ baseHost: this.host.policy.baseHost, handleShortcuts }),
      webContext: this.host.webContext,
      navigationHandler: (target) => this.onNavigation(target),
      newWindowHandler: (event) => this.onNewWindow(id, event),
    });
    this.tabs.set(id, { webview, url, title: title || hostOf(url), loading: true });

    webview.on('title-changed', ({ title: newTitle }) => this.updateTab(id, { title: newTitle?.trim() || hostOf(this.tabs.get(id)?.url) }));
    webview.on('page-load-started', ({ url: newUrl }) => this.updateTab(id, { loading: true, ...(newUrl ? { url: newUrl } : {}) }));
    webview.on('page-load-finished', ({ url: newUrl }) => this.updateTab(id, { loading: false, ...(newUrl ? { url: newUrl } : {}) }));
    webview.onIpcMessage(deferred((message) => this.onPageMessage(id, parse(message))));

    this.tabList.add(id, { after, activate });
    this.tabsChanged();
    return id;
  }

  /** Closing the last tab closes the window; closing the last window quits the app. */
  closeTab(id) {
    const tab = this.tabs.get(id);
    if (!tab) return;
    if (this.tabList.count === 1) {
      this.close();
      return;
    }
    this.tabList.remove(id);
    this.tabs.delete(id);
    tab.webview.dispose();
    this.tabsChanged();
  }

  selectTab(id) {
    this.tabList.select(id);
    this.tabsChanged();
    this.tabs.get(id)?.webview.focus();
  }

  updateTab(id, changes) {
    const tab = this.tabs.get(id);
    if (!tab) return;
    Object.assign(tab, changes);
    if (id === this.tabList.selectedId && changes.title) this.window.setTitle(changes.title);
    this.renderTabBar();
    if (changes.url) this.host.stateChanged();
  }

  tabsChanged() {
    if (this.closed) return;
    this.layout();
    const selected = this.tabs.get(this.tabList.selectedId);
    if (selected) this.window.setTitle(selected.title || this.host.config.name);
    this.renderTabBar();
    this.host.stateChanged();
  }

  // ---- Where links go ----

  /** Every navigation. Web pages always load (redirects and sign-in flows stay in the app); mailto: and the like go to their app. */
  onNavigation(url) {
    if (this.host.policy.destination(url) === 'system') {
      openExternally(url);
      return false;
    }
    return true;
  }

  /** target=_blank links and window.open: the app's own pages open as tabs, other sites in the browser. */
  onNewWindow(openerId, event) {
    const url = event?.url;
    if (!url || url === 'about:blank') return false;
    const destination = this.host.policy.destination(url);
    // A sized popup to another site (e.g. "Sign in with Google") opens as a tab so it can finish.
    if (destination === 'app' || (destination === 'browser' && event.windowFeatures?.size)) {
      setImmediate(() => this.openTab(url, { after: openerId, activate: true }));
    } else {
      openExternally(url);
    }
    return false;
  }

  onPageMessage(id, message) {
    if (!message) return;
    switch (message.type) {
      case 'open-external':
        if (/^https?:/.test(message.url)) openExternally(message.url);
        break;
      case 'open-tab':
        if (/^https?:/.test(message.url)) this.openTab(message.url, { after: id, activate: !message.background });
        break;
      case 'location':
        if (/^https?:/.test(message.url)) this.updateTab(id, { url: message.url });
        break;
      case 'command':
        this.runCommand(message.command);
        break;
    }
  }

  // ---- Commands (shortcuts, menu items) ----

  runCommand(command) {
    const selected = this.tabs.get(this.tabList.selectedId);
    switch (command) {
      case 'newTab': this.openTab(this.host.config.url); break;
      case 'closeTab': if (this.tabList.selectedId) this.closeTab(this.tabList.selectedId); break;
      case 'closeWindow': this.close(); break;
      case 'newWindow': this.host.openWindow({ tabs: [{ url: this.host.config.url }], selected: 0 }, { from: this }); break;
      case 'nextTab': TABS_SUPPORTED ? (this.tabList.selectOffset(1), this.tabsChanged()) : this.host.focusWindow(this, 1); break;
      case 'previousTab': TABS_SUPPORTED ? (this.tabList.selectOffset(-1), this.tabsChanged()) : this.host.focusWindow(this, -1); break;
      case 'reload': selected?.webview.reload(); break;
      case 'back': selected?.webview.evaluateScript('history.back()'); break;
      case 'forward': selected?.webview.evaluateScript('history.forward()'); break;
      case 'home': selected?.webview.loadUrl(this.host.config.url); break;
      case 'devtools': selected?.webview.openDevtools(); break;
      default: {
        const number = /^tab([1-9])$/.exec(command)?.[1];
        if (number && TABS_SUPPORTED) {
          this.tabList.selectNumber(Number(number));
          this.tabsChanged();
        } else if (number) {
          this.host.focusWindowNumber(Number(number));
        }
      }
    }
  }

  // ---- Saving and closing ----

  /** @returns {import('./session.js').WindowState} */
  snapshot() {
    const position = this.window.getPosition(true);
    const size = this.window.getInnerSize(true);
    return {
      tabs: this.tabList.ids.map((id) => {
        const tab = this.tabs.get(id);
        let url = tab.url;
        try {
          url = tab.webview.url() || url;
        } catch {
          // Webview already gone; use the last address we saw.
        }
        return { url, title: tab.title };
      }).filter((tab) => /^https?:/.test(tab.url)),
      selected: Math.max(0, this.tabList.selectedIndex),
      bounds: { x: position.x, y: position.y, width: size.width, height: size.height },
    };
  }

  close() {
    if (this.closed) return;
    this.onClosed();
    this.window.close();
  }

  onClosed() {
    if (this.closed) return;
    // Captured before the views go away, so the last window's tabs can be restored next launch.
    const finalState = this.snapshot();
    this.closed = true;
    setImmediate(() => this.host.windowClosed(this, finalState));
  }
}

/**
 * Wraps a handler for messages from a webview. It runs just after the native callback returns
 * (creating windows from inside one fails with "native value ... borrowed"), and errors are
 * reported instead of being swallowed by the native layer.
 */
export function deferred(handler) {
  return (...args) => setImmediate(() => {
    try {
      handler(...args);
    } catch (error) {
      console.error(error);
    }
  });
}

function parse(message) {
  try {
    return JSON.parse(Buffer.from(message.body).toString('utf8'));
  } catch {
    return null;
  }
}

function hostOf(url) {
  try {
    return new URL(url).hostname || 'New Tab';
  } catch {
    return 'New Tab';
  }
}
