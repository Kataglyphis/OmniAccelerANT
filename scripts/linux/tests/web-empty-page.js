#!/usr/bin/env node
// web-empty-page.js <check-docs-sidebars.js> <URL> <seconds> <max camera requests> <max socket attempts>: a page with nothing behind it must back off.
'use strict';

const { findChrome, launch, sleep } = require(process.argv[2]);

const READY = 'flutter-view, flt-glass-pane';

function fail(message, code = 2) {
  process.stderr.write(`web-empty-page: ${message}\n`);
  process.exit(code);
}

async function counts(url) {
  return (await fetch(new URL('/smoke-counts', url))).json();
}

async function main() {
  const [url, seconds, maxCamera, maxSockets] = [process.argv[3], ...process.argv.slice(4, 7).map(Number)];
  if (!url || ![seconds, maxCamera, maxSockets].every((n) => Number.isInteger(n) && n >= 0)) {
    fail('usage: web-empty-page.js <check-docs-sidebars.js> <page URL> <seconds> <max camera requests> <max socket attempts>');
  }
  const chrome = findChrome();
  if (!chrome) fail('no Chrome (CHROME_EXECUTABLE, chrome, chromium): the family image carries Chrome for Testing');
  const browser = await launch(chrome);
  let ready = false;
  let before;
  try {
    await browser.send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 800, deviceScaleFactor: 1, mobile: false });
    await browser.send('Page.navigate', { url });
    // The window starts once Flutter drew, so a slow boot under load cannot shorten what is measured.
    for (let i = 0; i < 600 && !ready; i++) {
      const found = await browser.send('Runtime.evaluate', { expression: `!!document.querySelector(${JSON.stringify(READY)})`, returnByValue: true });
      ready = found.result?.result?.value === true;
      if (!ready) await sleep(100);
    }
    if (!ready) fail(`${url} drew no Flutter view in 60 s`, 1);
    before = await counts(url);
    await sleep(seconds * 1000);
  } finally {
    await browser.close();
  }
  const after = await counts(url);
  const camera = after.camera - before.camera;
  const sockets = after.sockets - before.sockets;
  const paths = Object.entries(after.byPath).map(([p, n]) => `${p} ${n - (before.byPath[p] || 0)}`).join(', ');
  process.stdout.write(`web-empty-page: ${seconds} s of ${url}: ${camera} camera request(s) (${paths || 'none'}), `
    + `${sockets} socket attempt(s); ceilings ${maxCamera} and ${maxSockets}\n`);
  if (camera > maxCamera || sockets > maxSockets) fail('the page asked more often than a page that backs off does', 1);
  if (camera === 0 || sockets === 0) fail('the page never asked for the camera or the socket, so the count proves nothing', 1);
}

main().catch((e) => fail(e.stack || String(e)));
