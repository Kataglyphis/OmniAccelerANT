// node cdp-tab-return.mjs <debug-port> <url> <flag>: plays, hides the tab, silences its connections, shows it; one RETURN line.
import { writeFileSync } from 'node:fs';

const [, , debugPort, url, flag] = process.argv;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const version = await (await fetch(`http://127.0.0.1:${debugPort}/json/version`)).json();
const ws = new WebSocket(version.webSocketDebuggerUrl);
let nextId = 0;
const pending = new Map();
const send = (method, params = {}, sessionId) =>
  new Promise((resolve) => {
    const id = ++nextId;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params, sessionId }));
  });
ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  if (msg.id && pending.has(msg.id)) {
    pending.get(msg.id)(msg.result ?? msg.error);
    pending.delete(msg.id);
  }
};
await new Promise((resolve) => (ws.onopen = resolve));
const { targetInfos } = await send('Target.getTargets');
const page = targetInfos.find((t) => t.type === 'page');
const { sessionId } = await send('Target.attachToTarget', { targetId: page.targetId, flatten: true });
await send('Page.enable', {}, sessionId);
// The Stream page keeps its <video> in a shadow root; -1 when there is none.
const frames = async () =>
  (
    await send(
      'Runtime.evaluate',
      {
        returnByValue: true,
        expression: `(() => { let n = -1; const walk = (r) => { for (const el of r.querySelectorAll('*')) { if (el.tagName === 'VIDEO') n = Math.max(n, el.getVideoPlaybackQuality().totalVideoFrames); if (el.shadowRoot) walk(el.shadowRoot); } }; walk(document); return n; })()`,
      },
      sessionId,
    )
  ).result.value;
await send('Page.navigate', { url }, sessionId);
await sleep(20000);
const before = await frames();
// Another tab in front hides this one, as switching away does.
const other = await send('Target.createTarget', { url: 'about:blank' });
await send('Target.activateTarget', { targetId: other.targetId });
await sleep(5000);
writeFileSync(flag, '');
// Longer than the page's minute of grace, so its session closes while hidden.
await sleep(70000);
await send('Target.activateTarget', { targetId: page.targetId });
await send('Target.closeTarget', { targetId: other.targetId });
await sleep(10000);
const back = await frames();
await sleep(5000);
const later = await frames();
console.log(`RETURN ${JSON.stringify({ before, back, later })}`);
ws.close();
