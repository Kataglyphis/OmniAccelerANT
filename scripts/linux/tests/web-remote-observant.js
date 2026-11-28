#!/usr/bin/env node
// web-remote-observant.js <check-docs-sidebars.js> <build/web>: the Stream page's explicit ObservANT address in headless Chrome against a fixture ObservANT.
'use strict';

const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const http = require('node:http');
const https = require('node:https');
const os = require('node:os');
const path = require('node:path');

const { findChrome, launch, serve, sleep } = require(path.resolve(process.argv[2] || ''));

const KEY = 'omni_accelerant.observant_address';
const NAME = 'Fixture camera';
const READY = 'flutter-view, flt-glass-pane';
const WAIT_MS = 120000;
// ObservANT's own idle answer, the golden its status.rs checks at the OxidANT pin.
const IDLE = path.resolve(__dirname, '../../../third_party/OxidANT/crates/observant/tests/fixtures/healthz/idle.json');

// Thrown, never process.exit: the finally in main must still close Chrome, whose process group outlives this one.
class Failure extends Error {
  constructor(message, code = 1) {
    super(message);
    this.code = code;
  }
}

function fail(message, code = 1) {
  throw new Failure(message, code);
}

const listen = (server) => new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));

// A one-day certificate for app.test: Chrome runs with --ignore-certificate-errors, so only TLS itself matters.
function certificate(dir) {
  const key = path.join(dir, 'key.pem');
  const cert = path.join(dir, 'cert.pem');
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=app.test',
    '-addext', 'subjectAltName=DNS:app.test', '-keyout', key, '-out', cert], { stdio: 'ignore' });
  return { key: fs.readFileSync(key), cert: fs.readFileSync(cert) };
}

// The app as /app/ serves it: the hub's static handler behind COOP and COEP, once over http and once over https.
async function appServers(root, tls) {
  const plain = await serve(root);
  const files = plain.listeners('request')[0];
  plain.close();
  const isolated = (req, res) => {
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    files(req, res);
  };
  const app = http.createServer(isolated);
  const secure = https.createServer(tls, isolated);
  return { app, secure, httpPort: await listen(app), httpsPort: await listen(secure) };
}

// ObservANT's read rule (web.rs add_page_headers): CORS and CORP only for an origin in its peers, no preflight.
function observant(peers, seen) {
  const idle = JSON.parse(fs.readFileSync(IDLE, 'utf8'));
  return http.createServer((req, res) => {
    const where = new URL(req.url, 'http://fixture').pathname;
    const origin = req.headers.origin || '';
    seen.push({ method: req.method, path: where, origin });
    if (peers.includes(origin)) {
      res.setHeader('Access-Control-Allow-Origin', origin);
      res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
    }
    res.setHeader('Vary', 'origin');
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.writeHead(405, { 'Content-Type': 'text/plain' }).end('GET or HEAD only');
    } else if (where === '/healthz') {
      res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify({ ...idle, name: NAME }));
    } else {
      res.writeHead(404).end();
    }
  });
}

async function navigate(browser, url) {
  browser.loaded.length = 0;
  await browser.send('Page.navigate', { url });
  for (let i = 0; i < 600 && !browser.loaded.length; i++) await sleep(100);
  if (!browser.loaded.length) fail(`${url} did not load in 60 s`);
}

async function evaluate(browser, expression) {
  const answer = await browser.send('Runtime.evaluate', { expression, returnByValue: true });
  return answer.result?.result?.value;
}

// The page's words as a screen reader gets them: a click on Flutter's placeholder turns its semantics tree on.
const PAGE_TEXT = `(() => {
  document.querySelector('flt-semantics-placeholder')?.click();
  const host = document.querySelector('flt-semantics-host');
  if (!host) return '';
  const labels = [...host.querySelectorAll('[aria-label]')].map((e) => e.getAttribute('aria-label'));
  return [host.textContent, ...labels].join('\\n');
})()`;

// Opens the Stream page of `origin` with `address` saved, as a returning visitor; resolves with the text that matched.
async function visit(browser, origin, address, wanted) {
  await navigate(browser, `${origin}/manifest.json`);
  await evaluate(browser, `localStorage.setItem(${JSON.stringify(KEY)}, ${JSON.stringify(address)})`);
  await navigate(browser, `${origin}/?lang=en#/stream`);
  let text = '';
  for (let waited = 0; waited < WAIT_MS; waited += 500) {
    text = (await evaluate(browser, `!!document.querySelector(${JSON.stringify(READY)}) && ${PAGE_TEXT}`)) || '';
    if (wanted.every((w) => text.includes(w))) return text;
    await sleep(500);
  }
  return fail(`${origin} with ${address}: no ${JSON.stringify(wanted)} in ${WAIT_MS / 1000} s; the page said:\n${text.slice(0, 2000)}`);
}

// Sets this Chrome's Local Network Access choice for `origin` under every name it knows; returns the names it took.
async function localNetwork(browser, origin, setting) {
  const taken = [];
  for (const name of ['local-network-access', 'local-network', 'loopback-network']) {
    const answer = await browser.send('Browser.setPermission', { permission: { name }, setting, origin });
    if (!answer.error) taken.push(name);
  }
  if (!taken.length) fail('this Chrome takes no Local Network Access permission over DevTools, so the refusal cannot be set', 2);
  return taken;
}

async function main() {
  const root = path.resolve(process.argv[3] || 'build/web');
  if (!fs.existsSync(path.join(root, 'index.html'))) fail(`no web build at ${root}`, 2);
  const chrome = findChrome();
  if (!chrome) fail('no Chrome (CHROME_EXECUTABLE, chrome, chromium): the family image carries Chrome for Testing', 2);
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'web-remote-observant-'));
  const servers = [];
  let browser;
  try {
    const { app, secure, httpPort, httpsPort } = await appServers(root, certificate(work));
    servers.push(app, secure);
    const plainPage = `http://127.0.0.1:${httpPort}`;
    const securePage = `https://app.test:${httpsPort}`;
    const seen = [];
    const stub = observant([plainPage, securePage], seen);
    servers.push(stub);
    const stubPort = await listen(stub);
    const fromSecure = () => seen.filter((s) => s.origin === securePage);
    // app.test is the hosted site: Chrome places its server in the public address space, the fixture stays loopback.
    browser = await launch(chrome, ['--disable-gpu', '--ignore-certificate-errors',
      '--host-resolver-rules=MAP app.test 127.0.0.1, MAP observant.test 127.0.0.1',
      `--ip-address-space-overrides=127.0.0.1:${httpsPort}=public`]);
    process.stdout.write(`web-remote-observant: ${browser.product}, app on ${plainPage} and ${securePage}, ObservANT fixture on 127.0.0.1:${stubPort}\n`);
    await browser.send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });

    await visit(browser, plainPage, `http://127.0.0.1:${stubPort}`, [`Connected to ${NAME}`]);
    if (!seen.some((s) => s.path === '/healthz' && s.origin === plainPage)) fail('the http page connected without asking the fixture');
    process.stdout.write('PASS: an http page connects to an http ObservANT and names it\n');

    await visit(browser, securePage, `http://observant.test:${stubPort}`, ['(mixed content)', 'serve ObservANT over https']);
    if (fromSecure().length) fail(`the https page sent ${fromSecure().length} request(s) to an http address`);
    process.stdout.write('PASS: an https page refuses an http address with the mixed-content notice, unsent\n');

    const names = await localNetwork(browser, securePage, 'denied');
    await visit(browser, securePage, `http://127.0.0.1:${stubPort}`, ['Local network access is blocked for this site']);
    if (fromSecure().length) fail('the refused local-network request reached the fixture');
    // The page decided before sending; Chrome itself must refuse the same request, or the fixture proves nothing.
    const raw = await browser.send('Runtime.evaluate', { awaitPromise: true, returnByValue: true,
      expression: `fetch('http://127.0.0.1:${stubPort}/healthz').then(() => 'answered', () => 'refused')` });
    if (raw.result?.result?.value !== 'refused' || fromSecure().length) fail(`Chrome let the public page reach loopback under a denied permission (${raw.result?.result?.value})`);
    process.stdout.write(`PASS: a refused local-network permission (${names.join(', ')}) is named, unsent\n`);

    await localNetwork(browser, securePage, 'granted');
    await visit(browser, securePage, `http://127.0.0.1:${stubPort}`, [`Connected to ${NAME}`]);
    if (!fromSecure().some((s) => s.path === '/healthz')) fail('the allowed local-network request never reached the fixture');
    process.stdout.write('PASS: the same public page connects once local network access is allowed\n');

    if (browser.thrown.length) fail(`uncaught exception(s): ${browser.thrown.map((t) => t.text).join('; ')}`);
  } finally {
    if (browser) await browser.close();
    for (const server of servers) {
      server.closeAllConnections();
      server.close();
    }
    fs.rmSync(work, { recursive: true, force: true });
  }
}

main().catch((e) => {
  process.stderr.write(`web-remote-observant: ${e instanceof Failure ? e.message : e.stack || e}\n`);
  process.exitCode = e instanceof Failure ? e.code : 2;
});
