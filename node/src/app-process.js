// One wrapped app, in its own process. The launcher starts one of these per app and sends it
// the app's config and the windows to restore; this process reports its open tabs back as they
// change, so the launcher can save them.

import { mkdirSync } from 'node:fs';
import { Application } from '@webviewjs/webview';
import { AppWindow, deferred } from './app-window.js';
import { DEFAULT_TITLE_BAR_COLOR, fetchThemeColor } from './color.js';
import { LinkPolicy } from './links.js';
import { dataDirectory, loadIcon } from './system.js';

export class AppHost {
  /** @type {AppWindow[]} */
  windows = [];
  /** The last window's tabs as it closed, reported if the app quits because of it. */
  lastClosedState = null;
  reportTimer = null;
  exiting = false;

  /**
   * @param {import('./config.js').AppConfig} config
   * @param {{ themeColor: string | null, cascade: number }} options
   */
  constructor(config, { themeColor, cascade }) {
    this.config = config;
    this.policy = new LinkPolicy(config.url);
    this.titleBarColor = config.titleBarColor ?? themeColor ?? DEFAULT_TITLE_BAR_COLOR;
    this.icon = config.image ? loadIcon(config.image) : null;
    this.cascade = cascade;

    process.title = config.name;
    this.app = new Application();
    const directory = dataDirectory(config.id);
    mkdirSync(directory, { recursive: true });
    // Each app keeps its own cookies, storage and sign-ins.
    this.webContext = this.app.createWebContext({ dataDirectory: directory });
    if (process.platform === 'darwin') this.installMenu();
  }

  /** @param {import('./session.js').WindowState[]} windows */
  start(windows) {
    windows.forEach((state, index) => this.openWindow(state, { cascade: this.cascade + index }));
    this.app.run();

    // Use the site's theme color unless the config names one. A color saved last time shows
    // immediately; the fresh one replaces it when it arrives.
    if (!this.config.titleBarColor) {
      fetchThemeColor(this.config.url).then((color) => {
        if (!color || this.exiting) return;
        process.send?.({ type: 'theme-color', color });
        if (color === this.titleBarColor) return;
        this.titleBarColor = color;
        for (const window of this.windows) window.applyColor(color);
      });
    }
  }

  openWindow(state, placement = {}) {
    const window = new AppWindow(this, state, placement);
    this.windows.push(window);
    // A window opened from a link in the background (Ctrl+click) shouldn't take focus.
    if (placement.activate === false) placement.from?.window.focus();
    return window;
  }

  /** Where tabs open as windows (Linux): next/previous tab moves between the app's windows. */
  focusWindow(current, offset) {
    if (this.windows.length < 2) return;
    const index = this.windows.indexOf(current);
    this.windows.at((index + offset) % this.windows.length).window.focus();
  }

  focusWindowNumber(number) {
    const window = number === 9 ? this.windows.at(-1) : this.windows[number - 1];
    window?.window.focus();
  }

  windowClosed(window, finalState) {
    this.windows = this.windows.filter((w) => w !== window);
    if (this.windows.length === 0) {
      // Closing the app's last window quits it; its tabs are what reopen next time.
      this.lastClosedState = finalState;
      this.quit();
    } else {
      this.stateChanged();
    }
  }

  snapshot() {
    if (this.windows.length === 0) return this.lastClosedState ? [this.lastClosedState] : [];
    return this.windows.map((window) => window.snapshot());
  }

  /** Tells the launcher about tab changes, batched so a burst of events sends one message. */
  stateChanged() {
    if (this.exiting || this.reportTimer) return;
    this.reportTimer = setTimeout(() => {
      this.reportTimer = null;
      if (!this.exiting) process.send?.({ type: 'state', windows: this.snapshot() });
    }, 300);
  }

  /** Sends the final tabs, then exits. */
  quit() {
    if (this.exiting) return;
    let windows = [];
    try {
      windows = this.snapshot();
    } catch {
      // Native views already torn down; the launcher keeps the last state it received.
    }
    this.exiting = true;
    clearTimeout(this.reportTimer);
    const exit = () => {
      try {
        this.app.exit();
      } finally {
        process.exit(0);
      }
    };
    if (process.send && process.connected) process.send({ type: 'final', windows }, exit);
    else exit();
  }

  /** macOS: shortcuts come from the menu bar, which also makes Copy, Paste etc. work in pages. */
  installMenu() {
    const item = (id, label, accelerator) => ({ id, label, accelerator });
    this.app.setMenu({
      items: [
        // No "hide" role (its built-in ⌘H is Show Previous Tab here), and Quit goes through
        // quit() so the open tabs are saved.
        { label: this.config.name, submenu: { items: [{ role: 'hideothers' }, { role: 'separator' }, item('quit', `Quit ${this.config.name}`, 'CmdOrCtrl+Q')] } },
        {
          label: 'File',
          submenu: {
            items: [
              item('newTab', 'New Tab', 'CmdOrCtrl+T'),
              item('newWindow', 'New Window', 'CmdOrCtrl+N'),
              { role: 'separator' },
              item('closeTab', 'Close Tab', 'CmdOrCtrl+W'),
              item('closeWindow', 'Close Window', 'Shift+CmdOrCtrl+W'),
            ],
          },
        },
        {
          label: 'Edit',
          submenu: {
            items: [
              { role: 'undo' }, { role: 'redo' }, { role: 'separator' },
              { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectall' },
            ],
          },
        },
        {
          label: 'View',
          submenu: {
            items: [
              item('reload', 'Reload Page', 'CmdOrCtrl+R'),
              item('back', 'Back', 'CmdOrCtrl+['),
              item('forward', 'Forward', 'CmdOrCtrl+]'),
              item('home', 'Home', 'Shift+CmdOrCtrl+H'),
              { role: 'separator' },
              item('devtools', 'Developer Tools', 'Alt+CmdOrCtrl+I'),
              { role: 'separator' },
              { role: 'fullscreen' },
            ],
          },
        },
        {
          label: 'Window',
          submenu: {
            items: [
              item('previousTab', 'Show Previous Tab', 'CmdOrCtrl+H'),
              item('nextTab', 'Show Next Tab', 'CmdOrCtrl+L'),
              ...Array.from({ length: 9 }, (_, i) => item(`tab${i + 1}`, i === 8 ? 'Select Last Tab' : `Select Tab ${i + 1}`, `CmdOrCtrl+${i + 1}`)),
              { role: 'separator' },
              { role: 'minimize' },
            ],
          },
        },
      ],
    });
    this.app.on('custom-menu-click', deferred(({ customMenuEvent }) => {
      if (!customMenuEvent) return;
      if (customMenuEvent.id === 'quit') {
        this.quit();
        return;
      }
      const window = this.windows.find((w) => w.id === customMenuEvent.windowId) ?? this.windows.at(-1);
      window?.runCommand(customMenuEvent.id);
    }));
  }
}

// The launcher sends { type: 'init', app, windows, themeColor, cascade } once, and
// { type: 'shutdown' } when it's stopping.
let host = null;
process.on('message', (message) => {
  if (message?.type === 'init' && !host) {
    host = new AppHost(message.app, { themeColor: message.themeColor, cascade: message.cascade ?? 0 });
    host.start(message.windows);
  } else if (message?.type === 'shutdown') {
    host ? host.quit() : process.exit(0);
  }
});
// Ctrl+C in the terminal reaches every process; the launcher coordinates the shutdown instead.
process.on('SIGINT', () => {});
// If the launcher goes away, save nothing more and close.
process.on('disconnect', () => (host ? host.quit() : process.exit(0)));
