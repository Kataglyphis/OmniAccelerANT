// node page-perf.mjs <debug-port> <url> <seconds>: the boot timeline, the renderer it got, and what the open page costs.
const [, , debugPort, url, seconds] = process.argv;
const targets = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json();
const ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl);
let nextId = 0;
const pending = new Map();
const reqs = [];
const byId = new Map();
const ws_ = { created: null, firstSent: null, firstReceived: null, frames: [] };
const send = (method, params = {}) => new Promise((resolve) => { const id = ++nextId; pending.set(id, resolve); ws.send(JSON.stringify({ id, method, params })); });
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result ?? m.error); pending.delete(m.id); return; }
  const p = m.params;
  if (m.method === 'Network.requestWillBeSent' && /^https?:/.test(p.request.url)) { const r = { path: p.request.url.replace(/^https?:\/\/[^/]+/, '').split('?')[0], at: Date.now(), bytes: 0 }; reqs.push(r); byId.set(p.requestId, r); }
  if (m.method === 'Network.webSocketCreated') ws_.created ??= Date.now();
  if (m.method === 'Network.webSocketFrameSent') ws_.firstSent ??= Date.now();
  if (m.method === 'Network.webSocketFrameReceived') { ws_.firstReceived ??= Date.now(); if (ws_.frames.length < 8) ws_.frames.push([Date.now(), (p.response.payloadData || '').slice(0, 40)]); }
  if (m.method === 'Network.loadingFinished' && byId.has(p.requestId)) { const r = byId.get(p.requestId); r.bytes = p.encodedDataLength; r.done = Date.now(); }
};
await new Promise((r) => (ws.onopen = r));
await send('Network.enable');
await send('Network.setCacheDisabled', { cacheDisabled: true });
await send('Page.enable');
await send('Performance.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
await send('Page.addScriptToEvaluateOnNewDocument', { source: "window.__ff=null; window.addEventListener('flutter-first-frame', () => { window.__ff = performance.now(); });" });
const eval_ = async (expr) => (await send('Runtime.evaluate', { returnByValue: true, expression: expr })).result?.value;
const start = Date.now();
await send('Page.navigate', { url });
let video = null;
const videoExpr = `(() => { const f = []; const walk = (r) => { for (const el of r.querySelectorAll('*')) { if (el.tagName === 'VIDEO') f.push(el); if (el.shadowRoot) walk(el.shadowRoot); } }; walk(document); return f.some((v) => v.getVideoPlaybackQuality && v.getVideoPlaybackQuality().totalVideoFrames > 0); })()`;
const metric = async () => Object.fromEntries((await send('Performance.getMetrics')).metrics.map((x) => [x.name, x.value]));
let m1 = null; const total = Number(seconds) * 1000; const half = start + total / 2;
while (Date.now() - start < total) {
  await new Promise((r) => setTimeout(r, 250));
  if (video === null && (await eval_(videoExpr))) video = Date.now() - start;
  if (m1 === null && Date.now() >= half) m1 = { t: Date.now(), ...(await metric()) };
}
const m2 = { t: Date.now(), ...(await metric()) };
const env = await eval_(`({ secure: isSecureContext, isolated: crossOriginIsolated, imageDecoder: typeof ImageDecoder, breakIterator: typeof Intl.v8BreakIterator, firstFlutterFrame: window.__ff && Math.round(window.__ff) })`);
console.log(`secure context ${env.secure}, cross-origin isolated ${env.isolated}, ImageDecoder ${env.imageDecoder}, v8BreakIterator ${env.breakIterator}`);
console.log(`first Flutter frame ${env.firstFlutterFrame} ms, first video frame ${video ?? '-'} ms`);
const firstOf = {};
for (const r of reqs) if (r.at - start < 15000) firstOf[r.path] ??= r.at - start;
console.log(`first request per path: ${Object.entries(firstOf).filter(([, t]) => t > 400).sort((a, b) => a[1] - b[1]).map(([k, t]) => `${k} ${t}`).join(', ')}`);
const since = (t) => (t === null ? '-' : t - start);
console.log(`signalling socket: opened ${since(ws_.created)} ms, first sent ${since(ws_.firstSent)} ms, first received ${since(ws_.firstReceived)} ms`);
for (const [t, text] of ws_.frames) console.log(`  ws ${String(t - start).padStart(5)} ms ${text}`);
const boot = reqs.filter((r) => r.at - start < 15000 && r.bytes > 20000).sort((a, b) => a.at - b.at);
for (const r of boot) console.log(`  boot ${String(r.at - start).padStart(5)}..${String((r.done ?? r.at) - start).padStart(5)} ms ${(r.bytes / 1e3).toFixed(0).padStart(6)} kB ${r.path}`);
const window_s = (m2.t - m1.t) / 1000;
const late = reqs.filter((r) => r.at >= m1.t);
const counts = {};
for (const r of late) counts[r.path] = (counts[r.path] ?? 0) + 1;
console.log(`steady ${window_s.toFixed(0)} s: ${late.length} requests (${(late.length * 60 / window_s).toFixed(0)}/min): ${Object.entries(counts).map(([k, v]) => `${k} x${v}`).join(', ')}`);
console.log(`steady main thread: tasks ${(100 * (m2.TaskDuration - m1.TaskDuration) / window_s).toFixed(1)} %, script ${(100 * (m2.ScriptDuration - m1.ScriptDuration) / window_s).toFixed(1)} %, layout ${(100 * (m2.LayoutDuration - m1.LayoutDuration) / window_s).toFixed(1)} %; JS heap ${(m2.JSHeapUsedSize / 1e6).toFixed(0)} MB`);
ws.close();
