#!/usr/bin/env node
// Serves the compiled app and an idle ObservANT for the browser smoke; no camera or producer is advertised.
'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const root = path.resolve(process.argv[2]);
const port = Number(process.argv[3] || 8080);
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json', '.css': 'text/css',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon', '.woff2': 'font/woff2' };
const fixtures = {
  '/healthz': { ok: true, name: 'CI camera', camera: 'idle fixture', peers: [],
    frame: { width: 640, height: 480, fps: 0 }, detection: { count: 0 }, version: 'ci-fixture' },
  '/settings': { name: 'CI camera', rotate: 0, score: 0.25, ignore: [], classes: ['cat'] },
  '/visits': { visits: [] },
};
const server = http.createServer((req, res) => {
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  const rel = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  if (rel === '/snapshot.jpg') {
    const photo = path.join(root, 'assets/packages/anthology/assets/images/cats/Summy&Thundy_compressed.png');
    res.writeHead(200, { 'Content-Type': 'image/png' }).end(fs.readFileSync(photo));
    return;
  }
  if (Object.hasOwn(fixtures, rel)) {
    res.writeHead(200, { 'Content-Type': 'application/json' }).end(JSON.stringify(fixtures[rel]));
    return;
  }
  let file = path.resolve(root, `.${rel}`);
  if (!file.startsWith(`${root}${path.sep}`) && file !== root) { res.writeHead(403).end(); return; }
  if (file === root || (!fs.existsSync(file) && !path.extname(file))) file = path.join(root, 'index.html');
  fs.readFile(file, (err, body) => {
    if (err) { res.writeHead(404).end(); return; }
    res.writeHead(200, { 'Content-Type': types[path.extname(file)] || 'application/octet-stream' }).end(body);
  });
});

server.on('upgrade', (req, socket) => {
  if (req.url !== '/webrtc-ws' || !req.headers['sec-websocket-key']) { socket.destroy(); return; }
  const accept = crypto.createHash('sha1').update(`${req.headers['sec-websocket-key']}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`).digest('base64');
  socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
  const send = (value) => {
    const body = Buffer.from(JSON.stringify(value));
    socket.write(Buffer.concat([Buffer.from([0x81, body.length]), body]));
  };
  const peerId = crypto.randomUUID();
  let pending = Buffer.alloc(0);
  socket.on('error', () => {});
  socket.on('data', (chunk) => {
    pending = Buffer.concat([pending, chunk]);
    while (pending.length >= 2) {
      const opcode = pending[0] & 0x0f;
      let length = pending[1] & 0x7f;
      const masked = (pending[1] & 0x80) !== 0;
      let offset = 2;
      if (length === 127) { socket.destroy(); return; }
      if (length === 126) {
        if (pending.length < 4) return;
        length = pending.readUInt16BE(2); offset = 4;
      }
      const end = offset + (masked ? 4 : 0) + length;
      if (pending.length < end) return;
      const mask = pending.subarray(offset, offset + 4);
      const body = Buffer.from(pending.subarray(offset + (masked ? 4 : 0), end));
      pending = pending.subarray(end);
      if (masked) for (let i = 0; i < body.length; i++) body[i] ^= mask[i % 4];
      if (opcode === 8) { socket.end(Buffer.from([0x88, 0])); return; }
      if (opcode !== 1) continue;
      try {
        const message = JSON.parse(body.toString());
        if (message.type === 'setPeerStatus') send({ type: 'peerStatusChanged', peerId, roles: ['listener'] });
        else if (message.type === 'list') send({ type: 'list', producers: [] });
        else if (message.type === 'listConsumers') send({ type: 'listConsumers', consumers: [] });
        else { console.error(`unexpected signalling message: ${message.type}`); socket.destroy(); }
      } catch (err) { console.error(err); socket.destroy(); }
    }
  });
  send({ type: 'welcome', peerId });
});

server.listen(port, '127.0.0.1', () => console.log(`Web smoke fixture on http://127.0.0.1:${port}`));
