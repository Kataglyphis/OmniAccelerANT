#!/usr/bin/env node
// web-app-screenshot.js <URL> <out.png> [--size WxH] [--settle-ms N]: images/web-app.png in headless Chrome, the cookie notice pre-dismissed. See docs/source/project-operations.md
'use strict';

const fs = require('node:fs');
const path = require('node:path');
// The hub's launcher: one Chrome per run, its process group and profile cleaned up on every exit.
const { findChrome, launch, sleep } = require(path.join(__dirname, '../../third_party/ANTfrastructure/linux/scripts/check-docs-sidebars.js'));

const READY = 'flutter-view, flt-glass-pane';
const READY_MS = 60000;

function fail(message) {
  process.stderr.write(`web-app-screenshot: ${message}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const opts = { width: 1280, height: 800, settleMs: 8000, rest: [] };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--size') {
      [opts.width, opts.height] = String(argv[++i]).split('x').map(Number);
    } else if (argv[i] === '--settle-ms') {
      opts.settleMs = Number(argv[++i]);
    } else {
      opts.rest.push(argv[i]);
    }
  }
  if (opts.rest.length !== 2 || !/^https?:\/\//.test(opts.rest[0])) fail('usage: web-app-screenshot.js <URL> <out.png> [--size WxH] [--settle-ms N]');
  if (![opts.width, opts.height, opts.settleMs].every((n) => Number.isInteger(n) && n >= 0)) fail('--size takes WxH and --settle-ms a whole number');
  [opts.url, opts.out] = opts.rest;
  return opts;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const chrome = findChrome();
  if (!chrome) fail('no Chrome (CHROME_EXECUTABLE, chrome, chromium): the family image carries Chrome for Testing');
  const browser = await launch(chrome, ['--disable-gpu']);
  try {
    const { send } = browser;
    await send('Network.enable');
    // The cookie web/javascript/cookies.js sets on "Okay": the page then looks as a returning visitor sees it.
    await send('Network.setCookie', { name: 'cookie-consent', value: 'true', url: new URL('/', opts.url).href, path: '/' });
    await send('Emulation.setDeviceMetricsOverride', { width: opts.width, height: opts.height, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url: opts.url });
    const look = async (expr) => (await send('Runtime.evaluate', { expression: expr, returnByValue: true })).result.result.value;
    let ready = false;
    for (let waited = 0; waited < READY_MS && !ready; waited += 200) {
      ready = await look(`!!document.querySelector(${JSON.stringify(READY)})`);
      if (!ready) await sleep(200);
    }
    if (!ready) fail(`no ${READY} after ${READY_MS} ms: the app never started`);
    // Fonts and the first frames arrive after Flutter's view does.
    await sleep(opts.settleMs);
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    fs.writeFileSync(opts.out, Buffer.from(shot.result.data, 'base64'));
    process.stdout.write(`web-app-screenshot: ${opts.url} -> ${opts.out} (${opts.width}x${opts.height})\n`);
  } finally {
    await browser.close();
  }
}

main().catch((e) => fail(e.stack || String(e)));
