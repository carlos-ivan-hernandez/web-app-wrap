// Input cleanup and link routing, matching the macOS and Windows versions.

/**
 * Accepts "example.com", "https://example.com/app", "localhost:3000", etc. Returns a URL, or
 * null unless the result is an http(s) URL with a valid host.
 * @param {unknown} raw
 * @returns {URL | null}
 */
export function normalizeUrl(raw) {
  let text = typeof raw === 'string' ? raw.trim() : '';
  if (!text) return null;
  if (!text.includes('://')) {
    const lower = text.toLowerCase();
    const isLocal = ['localhost', '127.0.0.1', '0.0.0.0'].some((prefix) => lower.startsWith(prefix));
    text = (isLocal ? 'http://' : 'https://') + text;
  }
  let url;
  try {
    url = new URL(text);
  } catch {
    return null;
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
  if (!url.hostname || !/^[\p{L}\p{N}._\-[\]:]+$/u.test(url.hostname)) return null;
  return url;
}

/** Lowercase ASCII slug: "My Cool App!" -> "my-cool-app". Never empty. */
export function slug(name) {
  const folded = name.normalize('NFD').replace(/\p{Mn}/gu, '').toLowerCase();
  const result = folded.replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  return result || 'app';
}

/** Stable identifier for an app. Its storage folder and saved tabs are keyed by it. */
export function appId(name) {
  return `com.waw.app.${slug(name)}`;
}

function canonicalHost(host) {
  const lower = host.toLowerCase();
  return lower.startsWith('www.') ? lower.slice(4) : lower;
}

/**
 * Where a link should go: 'app' (load inside the app), 'browser' (default web browser), or
 * 'system' (the app that handles the scheme, for mailto:, tel:, zoommtg: and the like).
 */
export class LinkPolicy {
  /** @param {URL | string} baseUrl */
  constructor(baseUrl) {
    this.baseUrl = new URL(baseUrl);
    this.baseHost = canonicalHost(this.baseUrl.hostname);
  }

  /** @param {URL | string} url @returns {'app' | 'browser' | 'system'} */
  destination(url) {
    let parsed;
    try {
      parsed = new URL(url);
    } catch {
      return 'app';
    }
    switch (parsed.protocol) {
      case 'about:':
      case 'blob:':
      case 'data:':
      case 'javascript:':
        return 'app';
      case 'http:':
      case 'https:':
        return this.isInternalHost(parsed.hostname) ? 'app' : 'browser';
      default:
        return 'system';
    }
  }

  /** Same host as the base URL, or a subdomain of it. "www." is ignored on both sides. */
  isInternalHost(host) {
    if (!host) return false;
    const candidate = canonicalHost(host);
    return candidate === this.baseHost || candidate.endsWith(`.${this.baseHost}`);
  }
}
