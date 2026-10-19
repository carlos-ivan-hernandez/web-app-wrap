// The session file: every app's open windows and tabs, saved so the next launch restores them.
// It sits next to the config: apps.json -> apps.session.json.

import { readFile, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';

/**
 * @typedef {{ url: string, title?: string }} TabState
 * @typedef {{ x: number, y: number, width: number, height: number }} Bounds
 * @typedef {{ tabs: TabState[], selected: number, bounds?: Bounds }} WindowState
 * @typedef {{ name: string, windows: WindowState[], themeColor?: string }} AppSession
 * @typedef {{ version: 1, savedAt: string, apps: Record<string, AppSession> }} Session
 */

export function sessionPathFor(configPath) {
  const parsed = path.parse(path.resolve(configPath));
  return path.join(parsed.dir, `${parsed.name}.session.json`);
}

/** @returns {Promise<Session>} an empty session if the file is missing or unreadable */
export async function readSession(file) {
  try {
    const data = JSON.parse(await readFile(file, 'utf8'));
    if (data && typeof data.apps === 'object' && data.apps !== null) {
      return { version: 1, savedAt: data.savedAt ?? '', apps: sanitizeApps(data.apps) };
    }
  } catch {
    // Missing or damaged: start fresh.
  }
  return { version: 1, savedAt: '', apps: {} };
}

/** Writes atomically (temp file, then rename), so a crash mid-write never leaves a broken file. */
export async function writeSession(file, apps) {
  const session = { version: 1, savedAt: new Date().toISOString(), apps };
  const temporary = `${file}.tmp`;
  await writeFile(temporary, JSON.stringify(session, null, 2) + '\n');
  await rename(temporary, file);
}

/**
 * The windows to open for an app: what was saved last time, or one window with one tab at the
 * app's address.
 * @returns {WindowState[]}
 */
export function windowsToRestore(appSession, baseUrl) {
  const windows = (appSession?.windows ?? []).filter((window) => window.tabs.length > 0);
  return windows.length ? windows : [{ tabs: [{ url: baseUrl }], selected: 0 }];
}

function isWebUrl(value) {
  try {
    return ['http:', 'https:'].includes(new URL(value).protocol);
  } catch {
    return false;
  }
}

function finiteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

/** Drops anything malformed, so a hand-edited or damaged file can't break a launch. */
export function sanitizeApps(apps) {
  const result = {};
  for (const [id, app] of Object.entries(apps)) {
    if (!app || typeof app !== 'object') continue;
    const windows = (Array.isArray(app.windows) ? app.windows : [])
      .map((window) => {
        const tabs = (Array.isArray(window?.tabs) ? window.tabs : [])
          .filter((tab) => tab && isWebUrl(tab.url))
          .map((tab) => ({ url: tab.url, ...(typeof tab.title === 'string' ? { title: tab.title } : {}) }));
        const selected = Number.isInteger(window?.selected) ? Math.min(Math.max(window.selected, 0), Math.max(tabs.length - 1, 0)) : 0;
        const b = window?.bounds;
        const bounds = b && [b.x, b.y, b.width, b.height].every(finiteNumber) && b.width > 100 && b.height > 100
          ? { x: b.x, y: b.y, width: b.width, height: b.height }
          : undefined;
        return { tabs, selected, ...(bounds ? { bounds } : {}) };
      })
      .filter((window) => window.tabs.length > 0);
    result[id] = {
      name: typeof app.name === 'string' ? app.name : id,
      windows,
      ...(typeof app.themeColor === 'string' ? { themeColor: app.themeColor } : {}),
    };
  }
  return result;
}
