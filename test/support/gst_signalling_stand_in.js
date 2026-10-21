// ObservANT's side of gstwebrtc-api, in the page: the gst-plugins-rs signalling protocol and a webrtcsink-like producer.
const NativeWebSocket = window.WebSocket;
const NativePeerConnection = window.RTCPeerConnection;

// The camera every session sends: a canvas that changes every frame, so the video's frame count moves.
function startCamera(width, height) {
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  let frame = 0;
  setInterval(() => {
    context.fillStyle = frame++ % 2 ? "#204060" : "#60a040";
    context.fillRect(0, 0, width, height);
  }, 33);
  return canvas.captureStream(30);
}

// A socket as gstwebrtc-api's ComChannel uses one: onmessage, onclose, onerror, send and close, with task-ordered delivery.
class StandInSocket {
  constructor(server) {
    this.server = server;
    this.viewerId = `viewer-${server.sockets.length + 1}`;
    this.open = true;
    this.onmessage = null;
    this.onclose = null;
    this.onerror = null;
    server.sockets.push(this);
    if (!server.holdWelcome) this.welcome();
  }

  welcome() {
    this.deliver({ type: "welcome", peerId: this.viewerId });
  }

  deliver(msg) {
    setTimeout(() => {
      if (this.open && this.onmessage) this.onmessage({ data: JSON.stringify(msg) });
    }, 0);
  }

  send(text) {
    const msg = JSON.parse(text);
    // A WebSocket still connecting throws on send; ComChannel.send turns that into false.
    if (this.server.failSends.includes(msg.type)) {
      this.server.failSends.splice(this.server.failSends.indexOf(msg.type), 1);
      throw new DOMException("Still in CONNECTING state.", "InvalidStateError");
    }
    if (this.open) this.server.receive(this, msg);
  }

  close() {
    if (!this.open) return;
    this.open = false;
    setTimeout(() => this.onclose && this.onclose({ code: 1000 }), 0);
  }
}

class SignallingStandIn {
  constructor(url) {
    this.url = url;
    this.producers = [];
    this.sockets = [];
    this.sessions = [];
    this.received = [];
    this.consumerConfigs = [];
    this.refusedConfigs = [];
    this.failSends = [];
    this.holdWelcome = false;
    this.holdOffer = false;
    this.corruptOffers = 0;
    this.offerControlChannel = false;
    this.camera = startCamera(64, 48);
  }

  get session() {
    return this.sessions.filter((s) => !s.ended).pop() || null;
  }

  releaseWelcome() {
    this.holdWelcome = false;
    for (const socket of this.sockets) if (socket.open) socket.welcome();
  }

  releaseOffer() {
    this.holdOffer = false;
    for (const session of this.sessions) if (!session.ended && !session.pc) this.offer(session);
  }

  announce(id) {
    this.producers.push(id);
    this.broadcast({ type: "peerStatusChanged", peerId: id, roles: ["producer"], meta: {} });
  }

  // As the server does when a producer leaves: its sessions end, then listeners hear it is gone.
  withdraw(id) {
    this.producers = this.producers.filter((p) => p !== id);
    for (const session of this.sessions) if (session.producerId === id) this.endSession(session);
    this.broadcast({ type: "peerStatusChanged", peerId: id, roles: [], meta: {} });
  }

  endSession(session = this.session) {
    if (!session || session.ended) return;
    this.finish(session);
    session.socket.deliver({ type: "endSession", sessionId: session.id });
  }

  drop() {
    for (const session of this.sessions) this.finish(session);
    for (const socket of this.sockets) socket.close();
  }

  failNextSend(type) {
    this.failSends.push(type);
  }

  // The browser hides or shows the tab; Document.hidden has no setter.
  setHidden(hidden) {
    Object.defineProperty(document, "hidden", { configurable: true, get: () => hidden });
    document.dispatchEvent(new Event("visibilitychange"));
  }

  broadcast(msg) {
    for (const socket of this.sockets) if (socket.open && socket.listening) socket.deliver(msg);
  }

  finish(session) {
    session.ended = true;
    if (session.pc) session.pc.close();
  }

  receive(socket, msg) {
    this.received.push(msg.type);
    const session = this.sessions.find((s) => s.id === msg.sessionId);
    switch (msg.type) {
      case "setPeerStatus":
        socket.listening = msg.roles.includes("listener");
        socket.deliver({ type: "peerStatusChanged", peerId: socket.viewerId, roles: msg.roles, meta: msg.meta });
        break;
      case "list":
        socket.deliver({ type: "list", producers: this.producers.map((id) => ({ id, meta: {} })) });
        break;
      case "listConsumers":
        socket.deliver({ type: "listConsumers", consumers: [] });
        break;
      case "startSession":
        this.startSession(socket, msg.peerId);
        break;
      case "peer":
        if (session && !session.ended && msg.sdp) session.pc.setRemoteDescription(msg.sdp);
        if (session && !session.ended && msg.ice) session.pc.addIceCandidate(msg.ice);
        break;
      case "endSession":
        if (session) this.finish(session);
        break;
    }
  }

  startSession(socket, producerId) {
    if (!this.producers.includes(producerId)) {
      socket.deliver({ type: "error", details: `no producer ${producerId}` });
      return;
    }
    const session = { id: `session-${this.sessions.length + 1}`, producerId, socket, pc: null, ended: false, control: [] };
    this.sessions.push(session);
    socket.deliver({ type: "sessionStarted", peerId: producerId, sessionId: session.id });
    if (!this.holdOffer) this.offer(session);
  }

  // webrtcsink offers first, with the camera's track and, when enabled, the "control" data channel.
  async offer(session) {
    const pc = new NativePeerConnection();
    session.pc = pc;
    pc.onicecandidate = (event) => {
      if (event.candidate) session.socket.deliver({ type: "peer", sessionId: session.id, ice: event.candidate.toJSON() });
    };
    if (this.offerControlChannel) {
      pc.createDataChannel("control").onmessage = (event) => session.control.push(JSON.parse(event.data));
    }
    for (const track of this.camera.getTracks()) pc.addTrack(track, this.camera);
    await pc.setLocalDescription(await pc.createOffer());
    const sdp = this.corruptOffers > 0 ? { type: "offer", sdp: "v=0\r\ncorrupt\r\n" } : pc.localDescription.toJSON();
    if (this.corruptOffers > 0) this.corruptOffers--;
    if (!session.ended) session.socket.deliver({ type: "peer", sessionId: session.id, sdp });
  }
}

export function install(url) {
  const server = new SignallingStandIn(url);
  window.WebSocket = new Proxy(NativeWebSocket, {
    construct: (target, args) => (args[0] === url ? new StandInSocket(server) : new target(...args)),
  });
  // gstwebrtc-api builds its RTCPeerConnection from the view's config; this records what Chrome made of it.
  window.RTCPeerConnection = class extends NativePeerConnection {
    constructor(config) {
      try {
        super(config);
      } catch (error) {
        // gstwebrtc-api only logs it, so a test would see nothing but a session that never streams.
        server.refusedConfigs.push(`${error.name}: ${error.message}`);
        throw error;
      }
      server.consumerConfigs.push(this.getConfiguration());
    }
  };
  // flutter test renders no platform views, so the view's video is found where the view gives it a stream.
  const srcObject = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, "srcObject");
  Object.defineProperty(HTMLMediaElement.prototype, "srcObject", {
    configurable: true,
    get() {
      return srcObject.get.call(this);
    },
    set(stream) {
      server.video = this;
      srcObject.set.call(this, stream);
    },
  });
  server.video = null;
  return server;
}
