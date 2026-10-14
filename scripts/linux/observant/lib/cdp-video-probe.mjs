// node cdp-video-probe.mjs <debug-port> <url> <wait-ms>: one PROBE line, the boot overlay and every <video>, from a running Chrome.
const [, , debugPort, url, waitMs] = process.argv;
const targets = await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json();
const ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl);
let nextId = 0;
const pending = new Map();
const send = (method, params = {}) =>
  new Promise((resolve) => {
    const id = ++nextId;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });
ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  if (msg.id && pending.has(msg.id)) {
    pending.get(msg.id)(msg.result ?? msg.error);
    pending.delete(msg.id);
  }
};
await new Promise((resolve) => (ws.onopen = resolve));
await send('Page.enable');
await send('Page.navigate', { url });
await new Promise((resolve) => setTimeout(resolve, Number(waitMs)));
// The Stream page keeps its <video> in a shadow root, so the walk descends into each one.
const probe = await send('Runtime.evaluate', {
  returnByValue: true,
  expression: `(() => {
    const found = [];
    const walk = (root) => {
      for (const el of root.querySelectorAll('*')) {
        if (el.tagName === 'VIDEO') found.push(el);
        if (el.shadowRoot) walk(el.shadowRoot);
      }
    };
    walk(document);
    return JSON.stringify({
      bootOverlayGone: !document.querySelector('.loading'),
      videos: found.map((v) => ({
        width: v.videoWidth,
        height: v.videoHeight,
        frames: v.getVideoPlaybackQuality ? v.getVideoPlaybackQuality().totalVideoFrames : 0,
        paused: v.paused,
      })),
    });
  })()`,
});
console.log(`PROBE ${probe.result.value}`);
ws.close();
