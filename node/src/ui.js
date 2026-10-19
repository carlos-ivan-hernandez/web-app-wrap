// Code that runs inside the webviews: the tab bar page, and a script added to every web page.
// Both talk to Node with window.ipc.postMessage(JSON).

/**
 * Keyboard shortcuts for Windows and Linux, where there's no menu bar to catch them (macOS uses
 * the app menu instead). Maps a keydown to a command name, or null.
 */
const SHORTCUT_HANDLER = String.raw`
function webAppWrapShortcut(e) {
  if (e.key === 'F12' || (e.ctrlKey && e.shiftKey && e.key.toLowerCase() === 'i')) return 'devtools';
  if (e.key === 'F5') return 'reload';
  if (e.altKey && !e.ctrlKey && e.key === 'ArrowLeft') return 'back';
  if (e.altKey && !e.ctrlKey && e.key === 'ArrowRight') return 'forward';
  if (!e.ctrlKey || e.altKey || e.metaKey) return null;
  const k = e.key.toLowerCase();
  if (k === 'tab') return e.shiftKey ? 'previousTab' : 'nextTab';
  if (e.shiftKey) return k === 'w' ? 'closeWindow' : null;
  if (k === 't') return 'newTab';
  if (k === 'w') return 'closeTab';
  if (k === 'n') return 'newWindow';
  if (k === 'h') return 'previousTab';
  if (k === 'l') return 'nextTab';
  if (k === 'r') return 'reload';
  if (k >= '1' && k <= '9') return 'tab' + k;
  return null;
}`;

/**
 * Added to every web page before its own scripts.
 * - Clicked links to other sites go to the default browser; Ctrl/⌘-click and middle-click on the
 *   app's own links open a new tab. Redirects and scripted navigation are left alone, so sign-in
 *   flows keep working.
 * - Reports address changes made without a page load (single-page apps), so saved tabs are current.
 * - On Windows and Linux, forwards the tab shortcuts.
 */
export function pageScript({ baseHost, handleShortcuts }) {
  return String.raw`(() => {
  if (window.__webAppWrap || window.top !== window) return;
  window.__webAppWrap = true;
  const send = (message) => { try { window.ipc.postMessage(JSON.stringify(message)); } catch {} };
  const baseHost = ${JSON.stringify(baseHost)};
  const canonical = (host) => host.toLowerCase().replace(/^www\./, '');
  const isInternal = (url) => { const host = canonical(url.hostname); return host === baseHost || host.endsWith('.' + baseHost); };
  const isMac = /Mac|iPhone|iPad/.test(navigator.platform);

  function onLinkClick(e, background) {
    const link = e.target instanceof Element ? e.target.closest('a[href]') : null;
    if (!link) return;
    let url;
    try { url = new URL(link.href, location.href); } catch { return; }
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return;
    const modified = isMac ? e.metaKey : e.ctrlKey;
    if (!isInternal(url)) {
      e.preventDefault();
      e.stopImmediatePropagation();
      send({ type: 'open-external', url: url.href });
    } else if (modified || background) {
      e.preventDefault();
      e.stopImmediatePropagation();
      // Like browsers: Ctrl/⌘-click and middle-click open in the background; add Shift to switch to it.
      send({ type: 'open-tab', url: url.href, background: !e.shiftKey });
    }
  }
  document.addEventListener('click', (e) => { if (e.button === 0) onLinkClick(e, false); }, true);
  document.addEventListener('auxclick', (e) => { if (e.button === 1) onLinkClick(e, true); }, true);

  const reportLocation = () => send({ type: 'location', url: location.href });
  for (const method of ['pushState', 'replaceState']) {
    const original = history[method];
    history[method] = function (...args) { const result = original.apply(this, args); reportLocation(); return result; };
  }
  addEventListener('popstate', reportLocation);
  addEventListener('hashchange', reportLocation);

  ${handleShortcuts ? SHORTCUT_HANDLER + `
  addEventListener('keydown', (e) => {
    const command = webAppWrapShortcut(e);
    if (!command) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    if (command === 'back') history.back();
    else if (command === 'forward') history.forward();
    else if (command === 'reload') location.reload();
    else send({ type: 'command', command });
  }, true);` : ''}
})();`;
}

/**
 * The tab bar: tabs up to 240px wide with thin dividers, every tab in the bar's color, the
 * selected one marked only by brighter text. Drag a tab to reorder; middle-click closes.
 * Node calls window.render(state) to update it.
 */
export function tabBarHtml({ background, dark, handleShortcuts }) {
  const fg = dark ? '255,255,255' : '0,0,0';
  return String.raw`<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
  :root { color-scheme: ${dark ? 'dark' : 'light'}; }
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; overflow: hidden; background: ${background};
    font: 13px system-ui, -apple-system, "Segoe UI", Ubuntu, Cantarell, sans-serif;
    -webkit-user-select: none; user-select: none; }
  #strip { display: flex; height: 100%; align-items: stretch; padding-left: 6px; }
  .tab { position: relative; flex: 0 1 240px; min-width: 72px; display: flex; align-items: center;
    padding: 0 30px; color: rgba(${fg},0.55); cursor: default;
    border-left: 1px solid rgba(${fg},0.12); }
  .tab:last-of-type { border-right: 1px solid rgba(${fg},0.12); }
  .tab:hover, .tab.selected { color: rgba(${fg},0.95); }
  .tab.dragging { z-index: 2; background: ${background}; box-shadow: 0 0 0 1px rgba(${fg},0.15); opacity: 0.95; }
  .title { flex: 1; min-width: 0; overflow: hidden; white-space: nowrap; text-overflow: ellipsis; text-align: center; }
  .close, .spinner { position: absolute; top: 50%; width: 18px; height: 18px; margin-top: -9px; }
  .close { right: 8px; border: 0; border-radius: 4px; padding: 0; background: transparent; color: inherit;
    font-size: 15px; line-height: 18px; visibility: hidden; }
  .tab:hover .close, .tab.selected .close { visibility: visible; }
  .close:hover { background: rgba(${fg},0.12); }
  .spinner { left: 9px; width: 12px; height: 12px; margin-top: -6px; border-radius: 50%;
    border: 2px solid rgba(${fg},0.25); border-top-color: rgba(${fg},0.85); animation: spin 0.8s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  #new { flex: none; width: 36px; border: 0; background: transparent; color: rgba(${fg},0.55); font-size: 20px; }
  #new:hover { color: rgba(${fg},0.95); background: rgba(${fg},0.08); }
</style>
</head>
<body>
<div id="strip"><button id="new" title="New Tab">+</button></div>
<script>
  const send = (message) => window.ipc.postMessage(JSON.stringify(message));
  const strip = document.getElementById('strip');
  const newButton = document.getElementById('new');
  newButton.addEventListener('click', () => send({ type: 'new-tab' }));

  // Node re-renders after every change. While a tab is pressed the update waits, so the tab being
  // dragged isn't replaced mid-drag.
  let pressing = false;
  let pendingState = null;
  window.render = (state) => {
    if (pressing) pendingState = state;
    else draw(state);
  };

  function draw(state) {
    for (const old of strip.querySelectorAll('.tab')) old.remove();
    state.tabs.forEach((tab, index) => {
      const element = document.createElement('div');
      element.className = 'tab' + (index === state.selected ? ' selected' : '');
      element.title = tab.title;
      element.dataset.index = index;
      if (tab.loading) element.append(Object.assign(document.createElement('span'), { className: 'spinner' }));
      element.append(Object.assign(document.createElement('span'), { className: 'title', textContent: tab.title }));
      const close = Object.assign(document.createElement('button'), { className: 'close', textContent: '×', title: 'Close Tab' });
      close.addEventListener('pointerdown', (e) => e.stopPropagation());
      close.addEventListener('click', () => send({ type: 'close', index }));
      element.append(close);
      element.addEventListener('pointerdown', (e) => startPress(e, element, index));
      element.addEventListener('auxclick', (e) => { if (e.button === 1) send({ type: 'close', index }); });
      strip.insertBefore(element, newButton);
    });
  }

  // Click selects; dragging sideways reorders, with the other tabs sliding out of the way.
  function startPress(event, element, index) {
    if (event.button !== 0) return;
    event.preventDefault();   // no text selection or native drag while reordering
    pressing = true;
    const tabs = [...strip.querySelectorAll('.tab')];
    tabs.forEach((tab) => tab.classList.toggle('selected', tab === element));
    send({ type: 'select', index });
    const startX = event.clientX;
    const width = element.getBoundingClientRect().width;
    let target = index;
    let dragging = false;
    element.setPointerCapture(event.pointerId);

    const onMove = (e) => {
      const dx = e.clientX - startX;
      if (!dragging && Math.abs(dx) < 5) return;
      dragging = true;
      element.classList.add('dragging');
      const clamped = Math.max(-index * width, Math.min((tabs.length - 1 - index) * width, dx));
      element.style.transform = 'translateX(' + clamped + 'px)';
      target = Math.max(0, Math.min(tabs.length - 1, index + Math.round(clamped / width)));
      tabs.forEach((other, i) => {
        if (other === element) return;
        let shift = 0;
        if (i > index && i <= target) shift = -width;
        if (i < index && i >= target) shift = width;
        other.style.transition = 'transform 0.15s';
        other.style.transform = shift ? 'translateX(' + shift + 'px)' : '';
      });
    };
    const onUp = () => {
      element.removeEventListener('pointermove', onMove);
      element.removeEventListener('pointerup', onUp);
      element.removeEventListener('pointercancel', onUp);
      pressing = false;
      if (dragging && target !== index) {
        send({ type: 'move', from: index, to: target });   // Node re-renders in the new order
      } else {
        tabs.forEach((tab) => { tab.style.transform = ''; tab.classList.remove('dragging'); });
      }
      if (pendingState) {
        const state = pendingState;
        pendingState = null;
        draw(state);
      }
    };
    element.addEventListener('pointermove', onMove);
    element.addEventListener('pointerup', onUp);
    element.addEventListener('pointercancel', onUp);
  }

  ${handleShortcuts ? SHORTCUT_HANDLER + `
  addEventListener('keydown', (e) => {
    const command = webAppWrapShortcut(e);
    if (!command) return;
    e.preventDefault();
    send({ type: 'command', command });
  });` : ''}

  send({ type: 'ready' });
</script>
</body>
</html>`;
}
