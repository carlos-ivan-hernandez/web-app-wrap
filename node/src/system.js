// Small platform helpers: opening links outside the app, where app data lives, and window icons.

import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';
import { PNG } from 'pngjs';

/** Opens a URL with the system's default handler: the browser for web links, mail for mailto:, etc. */
export function openExternally(url) {
  const [command, args] =
    process.platform === 'win32' ? ['rundll32', ['url.dll,FileProtocolHandler', url]]
    : process.platform === 'darwin' ? ['open', [url]]
    : ['xdg-open', [url]];
  try {
    spawn(command, args, { detached: true, stdio: 'ignore', windowsHide: true }).on('error', () => {}).unref();
  } catch {
    // Nothing is registered to open it; nothing more to do.
  }
}

/**
 * Each app's own folder for cookies, storage and sign-ins.
 * Windows: %LOCALAPPDATA%\Web App Wrap\Node\<id>
 * macOS:   ~/Library/Application Support/Web App Wrap/Node/<id>
 * Linux:   $XDG_DATA_HOME (or ~/.local/share)/web-app-wrap/<id>
 */
export function dataDirectory(appId) {
  if (process.platform === 'win32') {
    return path.join(process.env.LOCALAPPDATA ?? path.join(homedir(), 'AppData', 'Local'), 'Web App Wrap', 'Node', appId);
  }
  if (process.platform === 'darwin') {
    return path.join(homedir(), 'Library', 'Application Support', 'Web App Wrap', 'Node', appId);
  }
  return path.join(process.env.XDG_DATA_HOME || path.join(homedir(), '.local', 'share'), 'web-app-wrap', appId);
}

/**
 * Reads a PNG as RGBA pixels for the window and taskbar icon, scaled down to at most 256px.
 * @returns {{ data: Uint8Array, width: number, height: number } | null}
 */
export function loadIcon(file) {
  try {
    const png = PNG.sync.read(readFileSync(file));
    return downscale({ data: png.data, width: png.width, height: png.height }, 256);
  } catch {
    return null;
  }
}

/** Box-filter downscale, so a 1024px PNG doesn't become a 4 MB icon. */
function downscale(image, maxSize) {
  const factor = Math.ceil(Math.max(image.width, image.height) / maxSize);
  if (factor <= 1) return image;
  const width = Math.floor(image.width / factor);
  const height = Math.floor(image.height / factor);
  const data = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const sum = [0, 0, 0, 0];
      for (let dy = 0; dy < factor; dy++) {
        for (let dx = 0; dx < factor; dx++) {
          const source = ((y * factor + dy) * image.width + (x * factor + dx)) * 4;
          for (let c = 0; c < 4; c++) sum[c] += image.data[source + c];
        }
      }
      const target = (y * width + x) * 4;
      for (let c = 0; c < 4; c++) data[target + c] = Math.round(sum[c] / (factor * factor));
    }
  }
  return { data, width, height };
}
