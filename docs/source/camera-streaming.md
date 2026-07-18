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
- **Display:** the native plugin (`Kataglyphis_NativeInferencePlugin`) exports a
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
`-Dgst-plugins-bad:mediafoundation=enabled` (ContainerHub
`windows/scripts/build-gstreamer-from-source.ps1`).

## WebRTC pipelines (Linux / web)

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