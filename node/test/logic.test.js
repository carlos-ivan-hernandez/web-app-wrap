import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, it } from 'node:test';
import { isDark, manifestUrl, parseCssColor, parseHex, themeColorFromHtml, themeColorFromManifest } from '../src/color.js';
import { ConfigError, parseConfig } from '../src/config.js';
import { LinkPolicy, appId, normalizeUrl, slug } from '../src/links.js';
import { readSession, sanitizeApps, sessionPathFor, windowsToRestore, writeSession } from '../src/session.js';
import { TabList } from '../src/tabs.js';

describe('links', () => {
  it('normalizes addresses', () => {
    assert.equal(normalizeUrl('example.com')?.href, 'https://example.com/');
    assert.equal(normalizeUrl('  app.example.com/dashboard ')?.href, 'https://app.example.com/dashboard');
    assert.equal(normalizeUrl('localhost:3000')?.href, 'http://localhost:3000/');
    assert.equal(normalizeUrl('http://example.com')?.href, 'http://example.com/');
    for (const bad of ['', '   ', 'ftp://example.com', 'not a url', 'https://', 42]) assert.equal(normalizeUrl(bad), null, String(bad));
  });

  it('makes slugs and ids', () => {
    assert.equal(slug('My Cool App!'), 'my-cool-app');
    assert.equal(slug('  Café   Crème '), 'cafe-creme');
    assert.equal(slug('🚀'), 'app');
    assert.equal(appId('Linear'), 'com.waw.app.linear');
  });

  it('routes links', () => {
    const policy = new LinkPolicy('https://app.example.com/home');
    const cases = {
      'https://app.example.com/settings': 'app',
      'http://APP.example.com': 'app',
      'https://www.app.example.com': 'app',
      'https://eu.app.example.com/x': 'app',
      'https://example.com': 'browser',
      'https://notapp.example.com': 'browser',
      'https://app.example.com.evil.io': 'browser',
      'mailto:someone@example.com': 'system',
      'zoommtg://zoom.us/join': 'system',
      'about:blank': 'app',
      'blob:https://app.example.com/abc': 'app',
    };
    for (const [url, expected] of Object.entries(cases)) assert.equal(policy.destination(url), expected, url);
  });
});

describe('colors', () => {
  it('parses hex and CSS colors', () => {
    assert.equal(parseHex('#1a1a1a'), '#1A1A1A');
    assert.equal(parseHex(' fff'), '#FFFFFF');
    assert.equal(parseHex('#12345'), null);
    assert.equal(parseCssColor('#1a1a1aff'), '#1A1A1A');
    assert.equal(parseCssColor('#abcd'), '#AABBCC');
    assert.equal(parseCssColor('rgb(26, 26, 26)'), '#1A1A1A');
    assert.equal(parseCssColor('rgb(100% 0% 0% / 50%)'), '#FF0000');
    assert.equal(parseCssColor('White'), '#FFFFFF');
    assert.equal(parseCssColor('hsl(0, 0%, 10%)'), null);
  });

  it('knows dark from light', () => {
    assert.ok(isDark('#1E1E1E'));
    assert.ok(!isDark('#F2F2F2'));
  });

  it('finds theme colors in HTML and manifests', () => {
    assert.equal(themeColorFromHtml('<meta\n  name="theme-color"\n  content="#1a1a1a"\n/>'), '#1A1A1A');
    assert.equal(themeColorFromHtml("<META content='#FFF' NAME=theme-color>"), '#FFFFFF');
    const variants = '<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#000"><meta name="theme-color" media="(prefers-color-scheme: light)" content="#eee">';
    assert.equal(themeColorFromHtml(variants), '#EEEEEE');
    assert.equal(themeColorFromHtml('<meta name="description" content="#abcdef">'), null);
    assert.equal(manifestUrl('<link rel="manifest" href="/manifest.webmanifest">', 'https://kphotos.vercel.app/login')?.href,
      'https://kphotos.vercel.app/manifest.webmanifest');
    assert.equal(themeColorFromManifest('{"theme_color":"#1a1a1a"}'), '#1A1A1A');
    assert.equal(themeColorFromManifest('nope'), null);
  });
});

describe('config', () => {
  const base = path.resolve('/configs');
  const errorOf = (json) => {
    try {
      parseConfig(json, base);
      return 'no error';
    } catch (error) {
      assert.ok(error instanceof ConfigError);
      return error.message;
    }
  };

  it('reads apps with defaults', () => {
    const [photos, linear] = parseConfig(JSON.stringify([
      { name: 'Web App Wrap/Photos', url: 'kphotos.vercel.app', image: 'icons/photos.png', zoom: 1.2, titleBarColor: '#1a1a1a' },
      { name: 'Linear', url: 'linear.app' },
    ]), base);
    assert.deepEqual(photos, {
      id: 'com.waw.app.photos', name: 'Photos', url: 'https://kphotos.vercel.app/',
      image: path.join(base, 'icons', 'photos.png'), titleBarColor: '#1A1A1A',
    });
    assert.equal(linear.image, null);
    assert.equal(linear.titleBarColor, null);
  });

  it('reports every problem at once', () => {
    const message = errorOf(JSON.stringify([
      { name: 'Good', url: 'good.com' },
      { url: 'nameless.com' },
      { name: 'Bad', url: 'not a url', zoom: 9, titleBarColor: 'teal', icon: 'x.png' },
      'oops',
    ]));
    assert.match(message, /Entry 2: “name” is missing\./);
    assert.match(message, /Entry 3 \(Bad\): unknown field “icon”/);
    assert.match(message, /“zoom” must be a number from 1 to 3/);
    assert.match(message, /“titleBarColor” must be a color/);
    assert.match(message, /Entry 4 isn’t an object\./);
    assert.doesNotMatch(message, /Entry 1/);
  });

  it('rejects bad files and duplicate names', () => {
    assert.equal(errorOf('not json'), 'The file isn’t valid JSON.');
    assert.equal(errorOf('{}'), 'The file must contain a JSON array of app objects.');
    assert.equal(errorOf('[]'), 'The array is empty.');
    assert.match(errorOf('[{"name":"Photos","url":"a.com"},{"name":"A/photos","url":"b.com"}]'), /same app name/);
  });
});

describe('tabs', () => {
  it('adds after the opener or at the end, and selects', () => {
    const tabs = new TabList();
    tabs.add('a');
    tabs.add('b');
    tabs.add('c', { after: 'a', activate: false });
    assert.deepEqual(tabs.ids, ['a', 'c', 'b']);
    assert.equal(tabs.selectedId, 'b');
  });

  it('selects the neighbor when the selected tab closes', () => {
    const tabs = new TabList();
    ['a', 'b', 'c'].forEach((id) => tabs.add(id));
    tabs.select('b');
    tabs.remove('b');
    assert.equal(tabs.selectedId, 'c');
    tabs.remove('c');
    assert.equal(tabs.selectedId, 'a');
    assert.equal(tabs.remove('zzz'), false);
  });

  it('cycles, jumps by number, and reorders', () => {
    const tabs = new TabList();
    ['a', 'b', 'c', 'd'].forEach((id) => tabs.add(id));
    tabs.selectOffset(1);
    assert.equal(tabs.selectedId, 'a');
    tabs.selectOffset(-1);
    assert.equal(tabs.selectedId, 'd');
    tabs.selectNumber(2);
    assert.equal(tabs.selectedId, 'b');
    tabs.selectNumber(9);
    assert.equal(tabs.selectedId, 'd');
    tabs.move(0, 2);
    assert.deepEqual(tabs.ids, ['b', 'c', 'a', 'd']);
    tabs.move(3, 0);
    assert.deepEqual(tabs.ids, ['d', 'b', 'c', 'a']);
  });
});

describe('session', () => {
  it('lives next to the config', () => {
    assert.equal(sessionPathFor('/x/apps.json'), path.resolve('/x/apps.session.json'));
  });

  it('round-trips and restores', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'waw-'));
    const file = path.join(dir, 'apps.session.json');
    const apps = { 'com.waw.app.photos': { name: 'Photos', windows: [{ tabs: [{ url: 'https://a.com/1' }, { url: 'https://a.com/2' }], selected: 1, bounds: { x: 10, y: 20, width: 900, height: 700 } }] } };
    await writeSession(file, apps);
    const session = await readSession(file);
    assert.deepEqual(session.apps, apps);
    assert.deepEqual(windowsToRestore(session.apps['com.waw.app.photos'], 'https://a.com/'), apps['com.waw.app.photos'].windows);
    assert.deepEqual(windowsToRestore(undefined, 'https://b.com/'), [{ tabs: [{ url: 'https://b.com/' }], selected: 0 }]);
  });

  it('survives missing and damaged files', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'waw-'));
    assert.deepEqual((await readSession(path.join(dir, 'missing.json'))).apps, {});
    const broken = path.join(dir, 'broken.json');
    await writeFile(broken, '{ nope');
    assert.deepEqual((await readSession(broken)).apps, {});
  });

  it('drops malformed entries', () => {
    const clean = sanitizeApps({
      a: { name: 'A', windows: [{ tabs: [{ url: 'javascript:alert(1)' }, { url: 'https://ok.com' }, null], selected: 7, bounds: { x: 0, y: 0, width: 5, height: 5 } }, { tabs: [] }] },
      b: 'junk',
    });
    assert.deepEqual(clean, { a: { name: 'A', windows: [{ tabs: [{ url: 'https://ok.com' }], selected: 0 }] } });
  });

  it('writes valid JSON', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'waw-'));
    const file = path.join(dir, 's.json');
    await writeSession(file, {});
    assert.equal(JSON.parse(await readFile(file, 'utf8')).version, 1);
  });
});
