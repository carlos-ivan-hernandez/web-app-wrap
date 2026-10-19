#!/usr/bin/env node
// npm start -- <apps.json> [--fresh]
//
// Opens every app in the config, each in its own window and its own process, restoring the tabs
// that were open last time. While running, and when everything shuts down, the open tabs are
// saved next to the config (apps.json -> apps.session.json) for the next launch.

import { fork } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ConfigError, loadConfig } from './config.js';
import { readSession, sessionPathFor, windowsToRestore, writeSession } from './session.js';

const USAGE = `Usage: npm start -- <apps.json> [--fresh]

  <apps.json>  A JSON array of apps: [{ "name": "Linear", "url": "linear.app" }, ...]
               Fields: name, url (required), image (PNG window icon), titleBarColor.
  --fresh      Ignore the saved tabs and open each app at its address.

Open tabs are saved to <apps>.session.json next to the config and restored next time.`;

const SHUTDOWN_TIMEOUT_MS = 5000;
const appProcessPath = fileURLToPath(new URL('./app-process.js', import.meta.url));

const args = process.argv.slice(2);
if (args.includes('--help') || args.includes('-h')) {
  console.log(USAGE);
  process.exit(0);
}
const configPath = args.find((arg) => !arg.startsWith('--')) ?? process.env.WEB_APP_WRAP_CONFIG;
if (!configPath) {
  console.error(`No config file given.\n\n${USAGE}`);
  process.exit(1);
}

let apps;
try {
  apps = await loadConfig(configPath);
} catch (error) {
  if (!(error instanceof ConfigError)) throw error;
  console.error(`${configPath} can’t be used:\n${error.message}`);
  process.exit(1);
}

const sessionFile = sessionPathFor(configPath);
const saved = args.includes('--fresh') ? { apps: {} } : await readSession(sessionFile);
// Everything in the saved session is kept, including apps temporarily removed from the config.
const state = { ...saved.apps };
const children = new Map();
let shuttingDown = false;

// ---- Saving ----

let saveTimer = null;
let saving = Promise.resolve();

function saveNow() {
  clearTimeout(saveTimer);
  saveTimer = null;
  saving = saving
    .then(() => writeSession(sessionFile, state))
    .catch((error) => console.error(`Couldn’t save open tabs to ${sessionFile}: ${error.message}`));
  return saving;
}

/** Saves shortly after changes settle, so a crash or power loss still leaves recent tabs. */
function saveSoon() {
  if (!saveTimer) saveTimer = setTimeout(saveNow, 1000);
}

// ---- App processes ----

function launch(app, index) {
  const child = fork(appProcessPath, [], { stdio: 'inherit', serialization: 'advanced' });
  children.set(app.id, child);

  child.send({
    type: 'init',
    app,
    windows: windowsToRestore(state[app.id], app.url),
    themeColor: state[app.id]?.themeColor ?? null,
    cascade: index,
  });

  child.on('message', (message) => {
    switch (message?.type) {
      case 'state':
      case 'final':
        if (message.windows.length > 0) state[app.id] = { ...state[app.id], name: app.name, windows: message.windows };
        saveSoon();
        break;
      case 'theme-color':
        state[app.id] = { ...state[app.id], name: app.name, windows: state[app.id]?.windows ?? [], themeColor: message.color };
        saveSoon();
        break;
    }
  });

  child.on('exit', (code, signal) => {
    children.delete(app.id);
    if (code && !shuttingDown) console.error(`${app.name} stopped unexpectedly (${signal ?? `exit code ${code}`}).`);
    if (children.size === 0) finish();
    else saveSoon();
  });
}

async function finish() {
  await saveNow();
  console.log(`Saved open tabs to ${sessionFile}`);
  process.exit(0);
}

/** Asks every app to save its tabs and close, then writes the session file. */
function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log('\nClosing apps…');
  for (const child of children.values()) {
    if (child.connected) child.send({ type: 'shutdown' });
  }
  setTimeout(() => {
    for (const child of children.values()) child.kill();
    finish();
  }, SHUTDOWN_TIMEOUT_MS).unref();
  if (children.size === 0) finish();
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
process.on('SIGHUP', shutdown);

console.log(`Opening ${apps.length} app${apps.length === 1 ? '' : 's'} from ${path.resolve(configPath)}. Press Ctrl+C to close them all.`);
apps.forEach(launch);
