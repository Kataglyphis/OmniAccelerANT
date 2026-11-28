# Browser port

This page plans the browser version of OmniAccelerANT. It lists what the app does today, the browser
equivalent of each function, and how local inference runs in a visitor's browser. The owner's decisions and
the steps in order are in [BACKLOG.md](../../BACKLOG.md) § *Open — browser/WebAssembly feature parity*.

The app will live at `/app/` on this repo's docs site. It runs its AI on the visitor's device with the
family's own ONNX Runtime Web builds. Today no model runs in the browser: the web build only shows boxes
that an ObservANT camera drew into its WebRTC picture.

## Inventory

| Function | Native today | Web today | In the browser | Risk |
| --- | --- | --- | --- | --- |
| Still-image detection | No page; only the CLI checks `--detect-check`, `--detect-latency`, `--onnx-check` and `--onnx-profile-image` (`lib/main.dart`) | None: each check is behind `!kIsWeb`, and OxidANT's wasm stub refuses | A new page: pick or drop an image, decode it to RGBA, run it in the worker, draw boxes and classes, show WebGPU or CPU, the ms per image and the model's provenance | Medium |
| Live webcam detection | Linux and Windows: `RustWebcamView`, with camera choice, threshold and class filter. Android: a preview without detection | None: `webcam_inference_available()` is false, and the plugin knows no web platform | `getUserMedia` and `enumerateDevices`, a `<video>` through `platformViewRegistry`, frames to the worker, boxes by `DetectionOverlayPainter`, fps and ms | High: needs a secure context, and threads need isolation |
| ObservANT stream (WebRTC, status, visits, peers) | A stub | Works when ObservANT serves the page. The own camera is the page's origin; peers are other origins | Stays. A remote mode with an explicit camera address joins it | Medium: see [Remote modes](#remote-modes) |
| Visit clips (`/arrival.mp4`) and "Not a cat" areas | A stub | Work against ObservANT | Stay remote functions | Low |
| Camera settings | Only a "camera not reachable" hint | Work against ObservANT | Stay for remote cameras; the local mode keeps its own settings in browser storage | Low |
| Text AI: AI Playground | Linux and Windows: an endpoint or the chain GenAI. Android: an endpoint | An endpoint only; *Local* is off, and OxidANT's wasm stub answers `LibraryUnavailable` | A generation loop of its own on the hub's ORT Web; the endpoint stays an explicit remote choice | High: see [Text AI](#text-ai) |
| Text AI on ObservANT (`/ask`, `/summary`) | None | Works | Stays a remote mode | Low |
| ESP32 device | Linux and Windows over Rust `serialport` | None: the page says the web has no serial port | Web Serial with the `no_std` protocol crate, and the link from a detection to the board | Medium: USB serial only in desktop Chromium |
| Storage | Files | The playground uses `localStorage`; SQLite on IndexedDB holds only the About page's health-check row | Cache Storage or OPFS keyed by SHA-256, `navigator.storage.persist()`, size and cache state shown | Medium |
| Files | Paths typed into text fields | Those fields are hidden | File picker, drag and drop, download as a blob | Low |
| Licenses page | The inventory with `files` keys for Android, Linux and Windows | Its own inventory, derived from the files `/app/` ships and gated: [project operations](project-operations.md#the-web-builds-license-inventory) | Done: the engine, Dart packages, wasm crates, ORT Web, the model texts, `gstwebrtc-api` with its `webrtc-adapter`, `sqlite3.wasm`, the fonts | Low: a file without an entry fails the build |
| Provenance | One line, "backend on provider" | Nothing about local inference | A panel: see [Provenance](#provenance) | Medium |
| Translations | English and German ARB files | The same | New texts for capabilities, fallback reasons, permissions and downloads. `stream_page.dart`, `rust_webcam_view.dart` and `device_page.dart` have no `AppLocalizations` yet | Low |
| About, blog, legal pages | Work | Work; `check-web-browser.sh` visits every route | No change. The About page's Rust `greet()` needs the core | Low |
| Rust core (flutter_rust_bridge) | Must load | Optional, with a timeout; Firefox and Safari do not load it without isolation | Browser inference never needs the core | High |
| `text_embed` | No Dart caller | None | Out of scope until a page uses it | Low |
| Hosting | Not needed | `/app/` on the docs site, built in `docs.yml`; `web.yml` still uploads an artifact, and the release skips it | Stays: see [Hosting](#hosting) | Medium |

## Architecture

```
Flutter UI (Dart)
  └─ InferenceBackend (interface; native: today's path, web: dart:js_interop)
       └─ dedicated Web Worker (JS module)
            ├─ vision_core wasm   → frame to NCHW float32
            ├─ ORT Web session    → WebGPU or CPU
            └─ vision_core wasm   → output rows to boxes
       ← results only: boxes, ms, the build chosen, the provider that ran
```

The worker keeps inference off the UI thread. The bridge's detector calls are synchronous, and ORT's own
proxy worker does not work with the WebGPU provider.

### Where each piece lives

| Piece | Repo |
| --- | --- |
| ORT Web per build, staged with a manifest of hashes and its license texts | hub `linux/scripts/lib/stage-ort-web.py` |
| The ORT-Web loader: build choice, capability probe, provenance JSON | hub `shared/web/` |
| A browser harness for ORT Web in headless Chrome, with detector parity | hub |
| The isolated-app `.htaccess` template and its test | hub |
| Header asserts in the live check | hub |
| The model mirror from the locks, with a web manifest | hub script, called here |
| `vision_core` as wasm, the COCO names, later the tokenizer and generation loop | OxidANT |
| The Dart backend, the worker binding, the pages, the provenance panel, translations, the web license part, the `/app/` build | here |

### ONNX Runtime Web

The hub's media image builds four ORT Web variants: CPU with SIMD and threads, JSEP, WebGPU through
Asyncify, and WebGPU through JSPI. The two WebGPU builds are reduced: no ML or generation ops, and fewer
types.

The app picks a build at run time:

1. JSPI, when `WebAssembly.Suspending` exists and a WebGPU adapter answers.
2. Asyncify, when only the adapter answers.
3. CPU otherwise.

JSEP ships only if the parity harness shows that DEIM fails on the reduced builds. DEIM uses `GridSample`,
`GatherElements` and `TopK`. WebNN stays off.

The JS bundles (`ort.*.mjs`) are built on amd64 only, so the site is built in an amd64 job. Ship a bundle
with the wasm of the same build, never a mix: ORT requires it. Never ship the `*.mjs.bak` files.

### Pre- and postprocessing

OxidANT's `crates/vision_core_web` wraps `vision_core` with wasm-bindgen. `vision_core` has no dependencies,
no I/O, no threads and no unsafe code, so the module needs no isolation. It preprocesses an RGBA, RGB or BGR
frame with its row stride, decodes the model's rows with the class count, and names the 80 COCO classes, so
labels never need the Rust core. A refusal throws a typed JS error. Its exports:
[OxidANT docs/crates.md](https://github.com/Kataglyphis/OxidANT/blob/develop/docs/crates.md). The contract
cases of ModelANT's `inference-v1.json` run on wasm32 in node and match the native results bit for bit.

DEIM-D-FINE-N takes `images` [1, 3, 640, 640], RGB, values 0 to 1, stretched. It returns `output0`
[1, 300, 6] as `xyxy_score_class`, with no NMS.

### Models

The locks are the source of truth. GitHub release downloads send no CORS header, so the site build fetches
each model with the hub's `fetch-data-lock.py` and mirrors it to the site's own origin. It writes a web
manifest with file, SHA-256, size and license files.

In the browser, `fetch` the file, check its SHA-256 with `crypto.subtle`, then cache it by hash. The hash
check is required: a missing `.onnx` can come back as `index.html` with status 200.

### Provenance

The panel shows:

- the build chosen and the ORT version
- the provider that ran, with the share of nodes per provider from a profile
- the GPU adapter's info
- `crossOriginIsolated` and the thread count
- the model's name, SHA-256 and ModelANT release
- on a CPU fallback, the reason: no secure context, not isolated, or no WebGPU

ORT puts nodes it cannot run on the CPU without a word, so the requested provider proves nothing. The hub's
`verify_ort_profile.py` checks the profile; it needs a WebGPU entry first.

### Flutter web

- Use `dart:js_interop` only; a Flutter wasm build has no `dart:html`.
- Use an interface, a stub and a web part behind a conditional import, as `observant_api_stub.dart` and
  `observant_api_web.dart` do.
- Firefox and Safari get dart2js and CanvasKit unless `wasmAllowList` is set, so test the web part under
  dart2js and dart2wasm.
- Capture the camera with own `getUserMedia` code; `camera_web` gives no frame stream.
- Send frames to the worker as a transferred `VideoFrame` or `ImageBitmap`. Only results come back.
- `web/flutter_bootstrap.js` registers Flutter's service worker. Check what it caches before the ORT and
  model paths go live.

### Text AI

Text AI comes after image detection, hosting and the webcam.

- There is no GenAI web build. The browser gets a generation loop of its own on the hub's ORT Web, in OxidANT:
  a tokenizer from `tokenizer.json`, the chat template, a KV cache (`past_key_values.*` in, `present.*` out),
  greedy decoding first and stop tokens.
- That is a second local engine, so the hub's language-AI plan changes first: its local-engine row and its
  web row.
- SmolLM2 needs com.microsoft ops: `MatMulNBits`, `GroupQueryAttention`, `GatherBlockQuantized` and
  `SkipSimplifiedLayerNormalization`. Its weights sit in an external `model.onnx.data`.
- The site build unpacks the archive with `fetch-data-lock.py --extract`. Its LICENSE and NOTICE are in
  ModelANT's `models/smollm2_135m_instruct/`, but the lock has no entries for them yet.
- A JSON schema is refused with a visible message. llguidance is pure Rust and could join the wasm module
  later.
- Test on the hub's tiny model first, then SmolLM2. Exact token ids on ORT's wasm CPU provider are a
  hypothesis; `must_contain` is the fallback rule.

### Remote modes

- An HTTPS page cannot query an `http://` ObservANT board (mixed content).
- Chrome asks for Local Network Access before a public page calls a private address or loopback, such as a
  board on the LAN or a local endpoint. The app needs a visible prompt and refusal path for it.
- Under COEP `require-corp`, snapshots from peers need CORS or a CORP header.
- ObservANT serves its page over plain HTTP in the LAN. There the browser has no WebGPU, no camera and no
  isolation, so the app offers no local inference there and says why.
- The public site sets no STUN server by default; the bundled settings name Google's.

The web build's Stream page has an **ObservANT address** field (`lib/Pages/StreamPage/remote/`). Empty, the
page asks the ObservANT that served it, as before. Filled, `observant_api_web.dart` sends every request,
picture and clip link to that origin; native builds keep their stub. The address must be `http://` or
`https://` with a host and nothing after it. It is kept in the browser's local storage under
`omni_accelerant.observant_address`. Before any request the page decides what the browser would do:

| Page and address | What the visitor sees |
| --- | --- |
| Any page, address answers `/healthz` | Connected, with the camera's name and version |
| `https` page, `http` address other than loopback | The mixed-content notice, no request: serve ObservANT over https (`serve.sh`, or a reverse proxy named in `allowed_hosts`), or open the app over http in the network, from the camera's own page |
| Address more private than the page: a public page and a LAN address or loopback | While Chrome's prompt is open, a line asking the visitor to choose Allow; the request then waits up to 60 s |
| The same, permission refused | The refusal and where to allow it (site settings, Local network access); no request while it stands |
| No answer the page may read | The address, the causes the page cannot tell apart (down, wrong address, CORS), and the page's origin, which ObservANT's `read_origins` must list |
| Timeout, error status, not ObservANT | Each its own line; an error status shows ObservANT's own reason |

The page places addresses by their form: loopback, RFC 1918 and link-local IPs, `localhost`, dotless names
and ObservANT's home-network suffixes. A name only DNS can place may ask. The permission is read through
the Permissions API under `local-network`, `loopback-network` or the older `local-network-access`. Its
`denied` before a request refuses at once. `denied` after a failed request tells a "Block" from a dead
host.

ObservANT answers another origin's reads only for the origins in its `peers` or `read_origins`, with CORS and
CORP. `read_origins` (OxidANT 06f0f63, owner decision) is the list for a page such as the hosted app: it reads
without being listed as a camera. It
refuses that origin's acting requests: `POST /settings`, `/ask` and the signalling socket. From another page,
status, visits and pictures work; the live picture, settings and questions stay on the camera's own page,
and the panel says so.

The check is `bash scripts/linux/check-web-browser.sh --remote [build dir]` in the image; the web lane runs
it after the other browser checks. `scripts/linux/tests/web-remote-observant.js` serves the build behind
COOP and COEP, over http and, with a throwaway certificate, as `https://app.test`. Chrome places that
server in the public address space (`--ip-address-space-overrides`). A fixture ObservANT on loopback answers
`/healthz` under ObservANT's `read_origins` rule. The check covers an http page connecting to an http address, the
https page refusing an http address with no request sent, and a denied permission refusing unsent. Under that
denial Chrome itself must refuse a plain `fetch` from the page, so the fixture reproduces the real block. Once
the permission is granted, the same page connects. The decisions themselves have unit tests:
`test/observant_address_test.dart`, `test/remote_access_test.dart`,
`test/remote_observant_controller_test.dart` and `test/remote_observant_panel_test.dart`.

## Hosting

The docs site is Apache, filled over FTP, and allows `.htaccess` with `Header` and `AddType`. The app is
built and uploaded in this repo's docs job, as BeschleunigerBallett publishes its `/webgpu-demo`
([hub docs-sites.md](https://github.com/Kataglyphis/ANTfrastructure/blob/develop/docs/docs-sites.md#proving-a-webgpu-page)).
It publishes on every push to develop or main after a green pipeline. The docs start page links it with a
picture or a short video.

`scripts/linux/build-docs-site.sh` runs `generate-docs.sh`, then builds the app with `--base-href /app/`
into `doc/api/app`. `docs.yml` passes `isolated-apps: app`, so the hub's stager copies the template into
`app/.htaccess` before the link gate. It also passes `live-url`, so the hub's `live-check` job runs
`check-live-site.js <site>/app/ --isolated` after each publish: the isolation headers, a boot without console
errors, and every published file answered with 200. By hand in the CI image:
`node third_party/ANTfrastructure/linux/scripts/check-live-site.js <site>/app/ --isolated`, and
`curl -sI` on `/app/` and on `/app/main.dart.wasm`.

The hosted build passes `--dart-define=OMNI_START_ROUTE=/aiPlayground`. The static host has no ObservANT, and the
camera page would call `/healthz` and the `/webrtc-ws` signalling socket there, so the app opens on the local-AI page.
`?lang=en` or `?lang=de` before the `#` picks the starting language, for example `/app/?lang=en#/aiPlayground`.
Without it, the app starts in the browser's first language it offers, otherwise in its first one; the language
menu changes it afterwards.
`scripts/linux/web-app-screenshot.js <URL> images/web-app.png` takes the README's picture in the CI image. It sets
the consent cookie first, so the cookie notice stays hidden as it does for a returning visitor.

`/app/.htaccess` comes from the hub's template for isolated apps and sets:

| Header or type | Value |
| --- | --- |
| `Cross-Origin-Opener-Policy` | `same-origin` |
| `Cross-Origin-Embedder-Policy` | `require-corp`; Safari has no `credentialless` |
| `Permissions-Policy` | `camera=(self)` |
| `.wasm` | `application/wasm` |
| `.mjs` | `text/javascript` |
| Files without a hash in the name (`main.dart.wasm`, `flutter_bootstrap.js`) | `no-cache` with an ETag |
| `ort/<version>-<build hash>/` and `models/<sha256>/` | `immutable` |

The rest of the docs site keeps the hub's docs-site `.htaccess`. The template jotrockenmitlocken deploys
stays unchanged.

## Tests

- **Detector parity**: DEIM on `two_cats.jpg` in each ORT build, against the native ORT CPU run, with the
  tolerances of the hub's `compare_detector_parity.py`, run CPU, GPU, then GPU again. The old rule holds too:
  at least two cats at 0.4 or more.
- **Preprocessing**: the digest cases of `inference-v1.json`, bit for bit.
- **CI**: headless Chrome in the image, WebGPU on SwiftShader. That proves the WebGPU code path, not a GPU.
  The CPU path runs with `--disable-gpu`.
- **Fallback and refusal paths**, each with its own test: a page without COOP and COEP, no WebGPU, no JSPI,
  the camera refused, a wrong hash, storage full, no Web Serial.
- **GPU proof**: a hand protocol on the owner's Windows, macOS or Intel Linux machine. It reads the adapter
  info and runs repeatedly.
- **Browsers**: Chromium on desktop and Android with WebGPU. Safari and Firefox with WebGPU where they have
  it, the CPU build where not, checked by a hand protocol: the image has only Chrome. JSPI needs Chrome 137,
  Firefox 153 or Safari 27.
- **Native regression**: the existing lanes stay unchanged.

## Traps

- The WebGPU builds are best effort: an image can come out without one. The stager must refuse a missing
  build instead of shipping fewer.
- ORT Web is built in the image, so the same version can produce new bytes. Take the hashes from the image's
  receipts when staging, never from a pinned list.
- ORT's file names carry no hash. A returning visitor could get a new `.mjs` with an old `.wasm`, so ORT files
  live under a path per build.
- Upstream's LICENSE and ThirdPartyNotices are missing from the image's web output until its next media build.
  Until then the hub's stager takes them from the image's onnxruntime wheel, and only when that wheel is the
  receipt's ORT version.
- `model.onnx.data` is large, and the FTP upload is slow: the first upload of the text model takes long.
