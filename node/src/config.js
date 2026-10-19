// Reads the apps config: the same JSON format as Web App Wrap's batch files on macOS and
// Windows, so one file works with all three.
//
//   [
//     { "name": "Photos", "url": "https://kphotos.vercel.app", "image": "icons/photos.png", "titleBarColor": "#1a1a1a" },
//     { "name": "Linear", "url": "linear.app" }
//   ]
//
// Only name and url are required. Folders in a name ("Web App Wrap/Photos") are accepted and
// ignored. image (a PNG, relative to the config file) becomes the window icon. zoom is accepted
// for compatibility and ignored. titleBarColor defaults to the site's theme color.

import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';
import { parseCssColor } from './color.js';
import { appId, normalizeUrl } from './links.js';

export class ConfigError extends Error {}

const KNOWN_FIELDS = new Set(['name', 'url', 'image', 'zoom', 'titleBarColor']);

/**
 * @typedef {{ id: string, name: string, url: string, image: string | null, titleBarColor: string | null }} AppConfig
 */

/**
 * Parses the config, or throws one ConfigError listing every problem found.
 * @param {string} json
 * @param {string} baseDirectory folder that relative image paths are resolved against
 * @returns {AppConfig[]}
 */
export function parseConfig(json, baseDirectory) {
  let root;
  try {
    root = JSON.parse(json);
  } catch {
    throw new ConfigError('The file isn’t valid JSON.');
  }
  if (!Array.isArray(root)) throw new ConfigError('The file must contain a JSON array of app objects.');
  if (root.length === 0) throw new ConfigError('The array is empty.');

  const apps = [];
  const problems = [];
  root.forEach((entry, index) => {
    const label = `Entry ${index + 1}`;
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      problems.push(`${label} isn’t an object.`);
      return;
    }
    const entryLabel = typeof entry.name === 'string' ? `${label} (${entry.name})` : label;
    const entryProblems = [];

    const unknown = Object.keys(entry).filter((key) => !KNOWN_FIELDS.has(key)).sort();
    if (unknown.length) entryProblems.push(`unknown field${unknown.length === 1 ? '' : 's'} ${unknown.map((u) => `“${u}”`).join(', ')}`);

    const name = typeof entry.name === 'string'
      ? entry.name.split(/[/\\]/).map((part) => part.trim()).filter((part) => part && part !== '.' && part !== '..').at(-1) ?? ''
      : '';
    if (!name) entryProblems.push('“name” is missing');

    const url = normalizeUrl(entry.url);
    if (!url) entryProblems.push('“url” is missing or isn’t a web address');

    let image = null;
    if (entry.image !== undefined && entry.image !== null) {
      if (typeof entry.image === 'string' && entry.image.trim()) image = resolvePath(entry.image.trim(), baseDirectory);
      else entryProblems.push('“image” must be a file path');
    }

    if (entry.zoom !== undefined && entry.zoom !== null && !(typeof entry.zoom === 'number' && entry.zoom >= 1 && entry.zoom <= 3)) {
      entryProblems.push('“zoom” must be a number from 1 to 3');
    }

    let titleBarColor = null;
    if (entry.titleBarColor !== undefined && entry.titleBarColor !== null) {
      titleBarColor = parseCssColor(entry.titleBarColor);
      if (!titleBarColor) entryProblems.push('“titleBarColor” must be a color like "#1a1a1a"');
    }

    if (entryProblems.length) problems.push(`${entryLabel}: ${entryProblems.join('; ')}.`);
    else apps.push({ id: appId(name), name, url: url.href, image, titleBarColor });
  });

  const seen = new Map();
  for (const app of apps) {
    if (seen.has(app.id)) problems.push(`“${seen.get(app.id)}” and “${app.name}” are the same app name; names must be unique.`);
    else seen.set(app.id, app.name);
  }

  if (problems.length) throw new ConfigError(problems.join('\n'));
  return apps;
}

export async function loadConfig(file) {
  let json;
  try {
    json = await readFile(file, 'utf8');
  } catch (error) {
    throw new ConfigError(`Couldn’t read ${file}: ${error.code === 'ENOENT' ? 'no such file' : error.message}`);
  }
  return parseConfig(json, path.dirname(path.resolve(file)));
}

function resolvePath(file, baseDirectory) {
  if (file === '~' || file.startsWith('~/') || file.startsWith('~\\')) file = path.join(homedir(), file.slice(2));
  return path.resolve(baseDirectory, file);
}
