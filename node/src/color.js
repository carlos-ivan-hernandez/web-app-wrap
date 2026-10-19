// Colors as "#RRGGBB", and finding a site's theme color.

export const DEFAULT_TITLE_BAR_COLOR = '#1E1E1E';

/** Accepts "#1a1a1a", "1A1A1A" or "#fff". Returns "#RRGGBB" or null. */
export function parseHex(hex) {
  let text = typeof hex === 'string' ? hex.trim() : '';
  if (text.startsWith('#')) text = text.slice(1);
  if (text.length === 3) text = [...text].map((c) => c + c).join('');
  return /^[0-9a-f]{6}$/i.test(text) ? `#${text.toUpperCase()}` : null;
}

/**
 * Parses the CSS forms sites use for theme colors: #rgb, #rgba, #rrggbb, #rrggbbaa,
 * rgb()/rgba() with numbers or percentages, and a few names. Alpha is ignored.
 * @returns {string | null} "#RRGGBB"
 */
export function parseCssColor(css) {
  const text = typeof css === 'string' ? css.trim().toLowerCase() : '';
  if (text === 'white') return '#FFFFFF';
  if (text === 'black') return '#000000';

  if (text.startsWith('#')) {
    let digits = text.slice(1);
    if (digits.length === 4) digits = digits.slice(0, 3);
    if (digits.length === 8) digits = digits.slice(0, 6);
    return parseHex(digits);
  }

  const match = /^rgba?\((.*)\)$/.exec(text);
  if (!match) return null;
  const parts = match[1].replace(/\//g, ' ').split(/[\s,]+/).filter(Boolean);
  if (parts.length < 3) return null;
  const channels = parts.slice(0, 3).map((part) => {
    const value = Number.parseFloat(part);
    if (Number.isNaN(value)) return null;
    return part.endsWith('%') ? value / 100 : value / 255;
  });
  if (channels.includes(null)) return null;
  return '#' + channels.map((c) => Math.round(Math.min(Math.max(c, 0), 1) * 255).toString(16).padStart(2, '0')).join('').toUpperCase();
}

/** True if text on this color should be light. */
export function isDark(hex) {
  const value = parseHex(hex) ?? DEFAULT_TITLE_BAR_COLOR;
  const [r, g, b] = [1, 3, 5].map((i) => Number.parseInt(value.slice(i, i + 2), 16) / 255);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.5;
}

// Minimal tag parsing: enough for <head> metadata, not a full HTML parser.
function tags(name, html) {
  const result = [];
  for (const [tag] of html.matchAll(new RegExp(`<${name}\\b[^>]*>`, 'gi'))) {
    const attributes = {};
    for (const m of tag.matchAll(/([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/g)) {
      const key = m[1].toLowerCase();
      attributes[key] ??= m[2] ?? m[3] ?? m[4] ?? '';
    }
    result.push(attributes);
  }
  return result;
}

/**
 * The first theme-color meta tag. Tags without a media query win over light/dark variants,
 * and a light variant wins over a dark one.
 */
export function themeColorFromHtml(html) {
  const candidates = tags('meta', html)
    .filter((tag) => tag.name?.toLowerCase() === 'theme-color')
    .map((tag) => {
      const media = tag.media?.toLowerCase() ?? '';
      return { color: parseCssColor(tag.content), rank: !media ? 0 : media.includes('dark') ? 2 : 1 };
    })
    .filter((candidate) => candidate.color)
    .sort((a, b) => a.rank - b.rank);
  return candidates[0]?.color ?? null;
}

/** The web app manifest linked from the page, resolved against the page's URL. */
export function manifestUrl(html, pageUrl) {
  const link = tags('link', html).find((tag) => tag.rel?.toLowerCase().split(/\s+/).includes('manifest') && tag.href);
  if (!link) return null;
  try {
    return new URL(link.href, pageUrl);
  } catch {
    return null;
  }
}

export function themeColorFromManifest(json) {
  try {
    const manifest = JSON.parse(json);
    return typeof manifest?.theme_color === 'string' ? parseCssColor(manifest.theme_color) : null;
  } catch {
    return null;
  }
}

/** Downloads the page (and its manifest if needed). Null if none is declared or the site can't be reached. */
export async function fetchThemeColor(url, { timeoutMs = 8000 } = {}) {
  // Node's fetch only tries IPv4 for "localhost", but local dev servers often listen on IPv6 only.
  const parsed = new URL(url);
  if (parsed.hostname === 'localhost') {
    for (const host of ['localhost', '[::1]']) {
      const color = await fetchThemeColorFrom(Object.assign(new URL(url), { hostname: host }).href, timeoutMs);
      if (color) return color;
    }
    return null;
  }
  return fetchThemeColorFrom(url, timeoutMs);
}

async function fetchThemeColorFrom(url, timeoutMs) {
  try {
    const signal = AbortSignal.timeout(timeoutMs);
    const response = await fetch(url, { signal, headers: { 'user-agent': 'Mozilla/5.0 (Web App Wrap)' } });
    const html = await response.text();
    const fromHtml = themeColorFromHtml(html);
    if (fromHtml) return fromHtml;
    const manifest = manifestUrl(html, response.url || url);
    if (!manifest) return null;
    return themeColorFromManifest(await (await fetch(manifest, { signal })).text());
  } catch {
    return null;
  }
}
