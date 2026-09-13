# Camera Streaming

Practical WebRTC streaming and inference pipelines for Kataglyphis.

## Windows: Rust-owned webcam inference (local, no WebRTC)

On Windows the **Stream** page runs a fully local webcam → ONNX → texture pipeline
owned end-to-end by Rust — no signalling server, no browser. Video frames never
cross the Dart bridge; only detection metadata does.

**Data flow:**

```
crates/media (gstreamer-rs)     src/webcam_engine.rs            src/api/webcam.rs (frb)
  mfvideosrc → ksvideosrc     ┌ pushes RGBA into the Flutter   ┌ list_cameras()
  → videoconvert → videoscale │ texture via the native plugin's│ start_webcam_inference()
  → RGBA appsink  ───────────►│ knt_push_frame C ABI           │   → Stream<DetectionEvent>
  (latest-frame slot)         └ runs PersonDetector (ONNX/ort) ─┘ stop_webcam_inference()
```

- **Rust source selection:** `mfvideosrc` (Media Foundation) is preferred, then
  `ksvideosrc`, then `autovideosrc`; `videotestsrc` is used for containers/CI (no
  camera). `mfvideosrc` requires the `mediafoundation` GStreamer plugin **and** a
  Windows *client* host (Server Core has no Media Foundation platform — see
  `platforms.md`). Without it the pipeline falls back to `ksvideosrc`.
- **Inference:** `ort` (ONNX Runtime) is loaded via `load-dynamic`
  (`ORT_DYLIB_PATH` → next-to-exe → `C:\runtime\lib\onnxruntime-source\bin`),
  DirectML execution provider with CPU fallback. Enabled by the crate features
  `gstreamer,onnxruntime_dynamic,onnxruntime_directml` (set for Windows via the
  `KATAGLYPHIS_RUST_FEATURES` env var, forwarded to cargo by the `rust_builder`
  CMake → Cargokit).
- **Display:** the native plugin (`packages/kataglyphis_native_inference`) exports a
  C ABI (`knt_create_texture` implied via the `create` method, `knt_push_frame`,
  `knt_api_version`) that Rust resolves with `libloading`. The Flutter UI is a
  `Texture(textureId)` with a `CustomPaint` box overlay fed by the
  `DetectionEvent` stream (`lib/Pages/StreamPage/rust_webcam_view.dart`).

**Run it:** launch the app (`Start-Windows.ps1`), open the **Stream** tab, pick a
camera (or *Test pattern*), optionally set a model path + score threshold, and
press **Start**. Bundled GStreamer plugins must include the capture source; the
build's DLL-bundling step stages `gstmediafoundation.dll`/`gstwinks.dll` +
GStreamer core DLLs into the runner. To get `mfvideosrc`, build against a
`windows-media` image whose GStreamer was compiled with
`-Dgst-plugins-bad:mediafoundation=enabled` (ANTfrastructure
`windows/scripts/build/Build-GstreamerFromSource.ps1`).

## WebRTC pipelines (Linux / web)

### Cat detection stream (Rust, native)

`third_party/OxidANT/crates/cat_webrtc` (`kataglyphis_cat_webrtc`) is the
maintained producer: V4L2 capture → YOLO ONNX (cats = COCO class 15) → boxes
burned into the RGBA frames → `webrtcsink`. It runs its own signalling server
(`run-signalling-server=true`, plain `ws://`, default port 8443), so no
separate signalling process is needed.

```bash
cd third_party/OxidANT
cargo build --release -p kataglyphis_cat_webrtc
ORT_DYLIB_PATH=/path/to/libonnxruntime.so \
  target/release/kataglyphis_cat_webrtc --v4l2 /dev/video0
```

`--test` streams a `videotestsrc` pattern, `--image <file>` loops a still image
(the default is ANThology's `Thundy.jpg` — defaults resolve relative to the
crate, so any checkout works). `--score`, `--width/--height/--fps`,
`--all-classes` and `--name` tune the stream. `--cert/--key` enable WSS on the
built-in server, but the signaller's rustls rejects self-signed CA certificates
(`CaUsedAsEndEntity`), so terminate TLS in a proxy instead — `serve.sh` does.

Serve the web build with the COOP/COEP headers the Stream page needs and the
`/webrtc-ws` proxy:

```bash
# once — web/pkg/ is a generated frb artefact (gitignored), so regenerate it
# the way the web CI lane does before building the frontend
rustup toolchain install nightly --component rust-src --target wasm32-unknown-unknown
cargo install flutter_rust_bridge_codegen
flutter_rust_bridge_codegen build-web --release --rust-root third_party/OxidANT
flutter build web --release

scripts/linux/cat-stream/serve.sh          # :8444 TLS, proxies to :8443
```

`signalingServerUrl` in `assets/settings/webrtc_settings.json` is
host-relative by default (`/webrtc-ws`); the web client resolves it against the
page's origin, so the same build works on localhost, a LAN IP and a Raspberry
Pi. Open `https://<host>:8444/` and accept the certificate warning. USB cameras
and, on Pi OS, the CSI camera through its V4L2 device work with `--v4l2`; if
`v4l2src` cannot open the device, the manual `libcamerasrc` pipeline below is
the fallback.

The numbered steps below are the manual `gst-launch-1.0` pipelines, kept for
cases the Rust producer does not cover.

## 1) Start the signalling server

```bash
cd /opt/gst-plugins-rs/net/webrtc/signalling
WEBRTCSINK_SIGNALLING_SERVER_LOG=debug cargo run --bin gst-webrtc-signalling-server -- --port 8444 --host 127.0.0.1
```

## 2) Export plugin path (if required)

```bash
export GST_PLUGIN_PATH=/home/user/gst-plugins-rs/target/release:$GST_PLUGIN_PATH
```

## 3) Start a stream source

### USB webcam

```bash
gst-launch-1.0 -e webrtcsink signaller::uri="ws://127.0.0.1:8444" name=ws \
  meta="meta,name=kataglyphis-webfrontend-stream" \
  v4l2src device=/dev/video0 ! image/jpeg,width=640,height=360,framerate=30/1 ! \
  jpegdec ! videoconvert ! ws.
```

### Pylon camera

```bash
gst-launch-1.0 -e webrtcsink signaller::uri="ws://127.0.0.1:8444" name=ws \
  meta="meta,name=kataglyphis-webfrontend-stream" \
  pylonsrc ! videoconvert ! ws.
```

### Raspberry Pi / Orange Pi (example)

```bash
GST_DEBUG=3 gst-launch-1.0 \
  libcamerasrc ! video/x-raw,format=RGB,width=640,height=360,framerate=30/1 ! \
  videoconvert ! video/x-raw,format=I420 ! queue ! \
  vp8enc deadline=1 threads=2 ! queue ! \
  webrtcsink signaller::uri="ws://0.0.0.0:8443" name=ws meta="meta,name=gst-stream"
```

## 4) Run the web frontend

```bash
flutter run -d web-server --profile --web-port 8080 --web-hostname 0.0.0.0
```

## 5) Python inference demos

Install dependencies:

```bash
sudo apt install -y libgirepository1.0-dev gir1.2-glib-2.0 \
  build-essential pkg-config python3-dev libgirepository-2.0-dev \
  gobject-introspection libcairo2-dev python3-gi python3-gi-cairo gir1.2-gtk-4.0
```

Optional virtual environment with system packages:

```bash
python3 -m venv --system-site-packages .venv
```

Run `demo_ai.py`:

```bash
uv venv
uv pip install loguru pygobject numpy opencv-python
GST_DEBUG=3 python3 demo_ai.py
```

Run `demo_yolov5.py`:

```bash
uv venv
uv pip install loguru pygobject numpy opencv-python
uv pip install torch==2.5.0 torchvision==0.20.0 torchaudio==2.5.0 --index-url https://download.pytorch.org/whl/cu121
uv pip install seaborn ultralytics
GST_DEBUG=3 python3 demo_yolov5.py
```

## Troubleshooting

- Use `GST_DEBUG=2` or `GST_DEBUG=3` to inspect pipeline performance and caps negotiation.
- Validate camera device permissions (`/dev/video*`) when streams fail to start.
- Ensure host/port pairs in `signaller::uri` match your signalling server.