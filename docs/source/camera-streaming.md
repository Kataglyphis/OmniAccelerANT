# Camera Streaming

Practical WebRTC streaming and inference pipelines for Kataglyphis.

## Rust-owned webcam inference (local, no WebRTC)

On Windows the **Stream** page runs a fully local webcam → ONNX → texture pipeline
owned end-to-end by Rust — no signalling server, no browser. Video frames never
cross the Dart bridge; only detection metadata does.

> **Linux has the same design as of 2026-09-16 — built, not yet seen working.**
> It is an *addition*: the WebRTC cat-stream below stays, and a Linux build with
> no `KATAGLYPHIS_RUST_FEATURES` keeps the C++ GStreamer MethodChannel path
> exactly as it is. All four links are in the tree — the `knt_push_frame` C ABI,
> the feature forwarding, ONNX Runtime bundling, and the Dart branch behind a
> runtime `listCameras()` probe.
>
> Build it with
> `KATAGLYPHIS_RUST_FEATURES=gstreamer,onnxruntime_dynamic` — **not**
> `onnxruntime_directml`, which is a Windows-only execution provider. Then check
> the ABI with `scripts/linux/check-knt-abi.sh` (see below).
>
> **No frame has actually reached the screen yet**, and the packaged artifacts do
> not carry their GStreamer dependency closure. BACKLOG.md tracks both, plus the
> model path a packaged build needs. Do not treat a green lane as a working
> camera.

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

### Checking the knt ABI

`scripts/linux/check-knt-abi.sh` verifies the C ABI the Rust webcam engine
depends on: that `knt_api_version` and `knt_push_frame` are exported from the
built plugin, are callable from outside the library, and return their
documented error codes (`-1` bad arguments, `-2` unknown texture id).

It exists because that ABI is resolved **by name at runtime** with `libloading`.
A rename, a dropped export or a visibility change is not a compile error on
either side — the app builds, ships, and then silently never shows a frame. The
script `dlopen`s the plugin exactly as Rust does, so a failure here is a failure
Rust would also hit.

It does not, and cannot, check that a real frame reaches the screen: frames end
in a GTK texture, and no lane has a `DISPLAY`. Seeing an actual frame needs a
Linux desktop session and a camera — on the Windows dev box that means the
`usbipd attach --wsl` route in AGENTS.md § 4.

Run it after a native build. The artefact is an ELF `.so`, so on a Windows host
it goes through a container, with the lane's build volume mounted:

```powershell
nerdctl run --rm --platform linux/amd64 `
  -v "C:\GitHub\OmniAccelerANT:/workspace" -w /workspace `
  --mount "type=volume,source=kataglyphis-lane-native-x64-workspace-build,target=/workspace/build" `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest-cross `
  bash scripts/linux/check-knt-abi.sh
```

Expected output:

```
ok   knt_api_version   = 1
ok   knt_push_frame    bad args -> -1
ok   knt_push_frame    unknown texture -> -2
knt ABI OK
```

## WebRTC pipelines (Linux / web)

### Cat detection stream (Rust, native)

`third_party/OxidANT/crates/cat_webrtc` (`kataglyphis_cat_webrtc`) is the
maintained producer: V4L2 or libcamera capture → YOLO ONNX (cats = COCO class
15) → boxes burned into the RGBA frames → `webrtcsink`. It runs its own
signalling server (`run-signalling-server=true`, plain `ws://`, default port
8443), so no separate signalling process is needed.

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

`--libcamera` captures through `libcamerasrc` instead of `v4l2src`; use it for
the Raspberry Pi CSI camera, whose `rp1-cfe` V4L2 nodes carry raw Bayer that
`videoconvert` cannot process. Inference runs on a background thread, so the
WebRTC stream keeps camera rate while the boxes lag one inference behind
(seconds per frame on a Pi 5 CPU). `--no-inference` skips the model entirely —
no ORT, no detector, frames published unannotated — for camera/WebRTC bring-up
and for hosts too weak to run YOLO. `--rotate 90|180|270` flips the stream with
`videoflip` (180 for a camera mounted upside down); inference sees the rotated
frame, so the boxes still line up.

Serve the web build with the COOP/COEP headers the Stream page needs and the
`/webrtc-ws` proxy:

```bash
# once — web/pkg/ is a generated frb artefact (gitignored), so regenerate it
# the way the web CI lane does before building the frontend
rustup toolchain install nightly --component rust-src --target wasm32-unknown-unknown
cargo install --locked --version 2.13.0 flutter_rust_bridge_codegen  # the pin in third_party/OxidANT/Cargo.toml
flutter_rust_bridge_codegen build-web --release --rust-root third_party/OxidANT
flutter build web --release --wasm --no-web-resources-cdn

scripts/linux/cat-stream/serve.sh          # :8444 TLS, proxies to :8443
```

`serve.sh` also takes `--producer-host`/`--producer-port` to front a producer
on another board, and `--state-dir` so several instances (one per producer)
can run side by side.

`signalingServerUrl` in `assets/settings/webrtc_settings.json` is
host-relative by default (`/webrtc-ws`); the web client resolves it against the
page's origin, so the same build works on localhost, a LAN IP and a Raspberry
Pi. Open `https://<host>:8444/` and accept the certificate warning.

USB cameras work with `--v4l2 /dev/videoX`. For a Pi's CSI camera use
`--libcamera`; on a Raspberry Pi 5 running the `:latest-cross` image the
container route is:

```bash
# The producer runner lives in OxidANT, which owns crates/cat_webrtc.
third_party/OxidANT/scripts/linux/cat-stream/run-producer-pi.sh --build
scripts/linux/cat-stream/serve.sh   # :8444 TLS, proxies to :8443
```

**Why the Pi 5 needs a runner script.** The image ships upstream libcamera
0.7.2 / libpisp 1.5, which cannot drive a Pi 5 on kernel 6.18: the kernel
renamed the `rp1-cfe` media entities to underscores (`rp1-cfe-fe_image0`) and
moved to the libpisp 1.7 uAPI, so the pipeline handler cannot acquire the CFE
and the upstream IPA segfaults when isolation is forced. Build with the runner
(`--build`): it mounts OxidANT at `/workspace`, and a binary built from the
superproject layout instead carries a compiled-in model path pointing at
`/workspace/third_party/OxidANT/resources/...`, which does not exist under that
mount — the producer then dies with `No ONNX backend available`. Cargo caches
by source mtime, so after switching contexts `touch crates/cat_webrtc/src/main.rs`
forces the recompile.
`third_party/OxidANT/scripts/linux/cat-stream/run-producer-pi.sh` collects the
host's Raspberry Pi OS libcamera stack (0.7.2+rpt, which matches the kernel)
plus its library closure into OxidANT's own
`third_party/OxidANT/build/cat-stream/hostlibs`, mounts that ahead of
the image's copy, grants the rootless container ACL access to
`/dev/{video,media,dma_heap}*`, and runs with `seccomp=unconfined` (the IPA
proxy forks). GStreamer 1.29, `webrtcsink`, ONNX Runtime and the Rust binary
still come from the image.

**Raspberry Pi Zero 2 W.** The image runs there too, but the Rust producer
does not fit the board (512 MB RAM, no practical way to build on it), and the
image's libcamera cannot drive the Zero's camera either: with `rpi/vc4` on the
imx708 its isolated IPA process worker dies on start (`Failed to call start:
-110`, then the socket is unreachable), while the host's rpt build runs the
threaded proxy and works. The working no-AI recipe is the container plus the
*same* host-libcamera swap, driven by `gst-launch`. Copy the closure collected
by OxidANT's `third_party/OxidANT/scripts/linux/cat-stream/run-producer-pi.sh`
(or refresh it there with `--libs-only`) to the Zero, then:

```bash
# On the Zero. ~/cat-cam/hostlibs is the dev host's
# third_party/OxidANT/build/cat-stream/hostlibs, and IMAGE is the family CI
# reference — composed on the dev host by
#   bash third_party/ANTfrastructure/linux/scripts/ci-image-ref.sh
# and carried over, never typed out, so a tag bump in the hub's versions.env
# reaches this recipe too.
IMAGE=<the line that command printed>
sudo nerdctl run --rm --name zero-producer --user 0:0 --privileged \
  --network host -v /dev:/dev -v /run/udev:/run/udev:ro \
  -v /usr/lib/aarch64-linux-gnu/libcamera:/usr/lib/aarch64-linux-gnu/libcamera:ro \
  -v /usr/share/libcamera:/usr/share/libcamera:ro \
  -v "$HOME/cat-cam/hostlibs":/hostlibs:ro \
  -e LD_LIBRARY_PATH=/hostlibs:/opt/gstreamer/lib/multiarch:/opt/gstreamer/lib:/usr/local/lib:/opt/opencv5/lib:/usr/lib/aarch64-linux-gnu \
  --entrypoint bash "${IMAGE}" \
  -lc 'exec gst-launch-1.0 -e \
    webrtcsink name=ws run-signalling-server=true signalling-server-host=0.0.0.0 signalling-server-port=8443 meta="meta,name=Zero-Cat-Cam" \
    libcamerasrc ! video/x-raw,format=RGB,width=640,height=480,framerate=15/1 ! videoconvert ! videoflip method=rotate-180 ! video/x-raw,format=I420 ! vp8enc deadline=1 ! ws.'
```

The `videoflip` is there because this Zero's camera is mounted upside down
(drop it, or change the method, for an upright camera — `--rotate` is the
producer's equivalent).

Two traps bite anyone wiring this by hand: the image's `entrypoint.sh` sources
`libcamera-env.sh`, which re-prepends `/opt/libcamera/lib` and silently
overrides the `LD_LIBRARY_PATH` above — hence `--entrypoint bash`; and
`webrtcsink`'s `meta` must be a space-free structure in gst-launch
(`meta="meta,name=Zero-Cat-Cam"`; a space fails to parse). The dev host's
`serve.sh` (:8444) fronts the Zero without deploying the web build to it, by
tunnelling only the signalling:

```bash
ssh -N -L 8443:127.0.0.1:8443 himbeergsaelzlight.local   # run on the dev host
```

Media is WebRTC UDP, browser ↔ Zero, direct on the LAN. If the container is
too heavy for the board, `scripts/linux/cat-stream/package-producer-bundle.sh`
exports a container-less aarch64 bundle (producer + pruned GStreamer + the
image's glibc, ~180 MB) that runs against the host's libcamera with no
container and no toolchain; and `--no-inference` is the next step up from this
`gst-launch` bring-up.

**Other VC4/unicam Pis (e.g. Pi 4).** The same host-libcamera swap applies,
but the Rust producer fits there: run it in the container with the `hostlibs`
mount and `--libcamera` (that is `~/zweckle-producer.sh` on the Pi 4, name
`Zweckle Cat Cam`). Two extra bits beyond the Zero: the `/dev/dma_heap/*`
nodes need the same ACL as the camera nodes, or libcamera reports
`Could not open any dma-buf provider` and registration fails with `-12`
(ENOMEM); and `/opt/gcc-16.2.0/lib64` must be on `LD_LIBRARY_PATH`, or the
image's ONNX Runtime dies with `GLIBCXX_3.4.36 not found` (the image's GCC 16
libstdc++ is what ORT was built against). The Pi 4's camera here is mounted
upside down, so its runner passes `--rotate 180`.

**RISC-V SoC (SpacemiT X100).** `:latest-cross` is a multi-arch index
(amd64/arm64/riscv64), so the same tag runs there natively and the producer
builds inside the container in minutes on 8 cores — GStreamer, `v4l2src` and
ONNX Runtime are all riscv64 builds in the image. A USB webcam (e.g. a
Logitech C270) needs no libcamera: run with `--v4l2 /dev/videoN`. On Ubuntu
the host-level work is permissions and firewall: the node is `root:video 660`
and the user is usually not in `video`, so grant an ACL
(`sudo setfacl -m u:$USER:rw /dev/videoN`), and UFW needs `8443/tcp` plus the
WebRTC UDP range (`sudo ufw allow 32768:60999/udp`) because the browser
connects directly to the board for media. The dev host can front it without
deploying the web build:

```bash
scripts/linux/cat-stream/serve.sh --port 8446 \
  --producer-host 192.168.188.146 --producer-port 8443 \
  --state-dir build/cat-stream/x100
```

Use the board's **IP, not its mDNS name**, in `--producer-host`: nginx
resolves `proxy_pass` hostnames once at startup, so a DHCP or mDNS address
change leaves it proxying into the void with a `101` in the access log and no
connection on the producer.

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

## Troubleshooting

- Use `GST_DEBUG=2` or `GST_DEBUG=3` to inspect pipeline performance and caps negotiation.
- Validate camera device permissions (`/dev/video*`) when streams fail to start.
- Ensure host/port pairs in `signaller::uri` match your signalling server.
- If the page loads but the app never starts, check the `main.dart.mjs`
  `Content-Type`: Flutter's wasm bootstrap loads it with a dynamic `import()`,
  which browsers reject for `application/octet-stream`. `serve.sh` maps `.mjs`
  to `application/javascript` for exactly that reason.
- The same trap one extension over, and the one likelier to bite on an older
  board: nginx added `application/wasm` to its bundled `mime.types` in 1.21.x,
  so Debian bullseye, Raspberry Pi OS bullseye and Ubuntu 22.04 (all nginx
  1.18.0) serve `main.dart.wasm` as `application/octet-stream` and
  `WebAssembly.compileStreaming()` refuses it — a blank page with nothing in the
  console naming the cause. `serve.sh` declares `.wasm` itself so the nginx
  version stops mattering; if you serve the build some other way, check it with
  `curl -kI https://<host>:8444/main.dart.wasm | grep -i content-type`.
- A browser that reports `ERR_CERT_COMMON_NAME_INVALID` and offers no
  click-through is holding a certificate generated before `serve.sh` started
  writing a `subjectAltName`. The cert is cached in `--state-dir`, and `serve.sh`
  now regenerates a CN-only one on sight — but if you pinned or exported the old
  one, delete `build/cat-stream/tls/` and let it rebuild.
- On a host firewall (e.g. UFW on Raspberry Pi OS), allow `8444/tcp` and the
  WebRTC media UDP range (`32768:60999/udp`, LAN-scoped is enough) — the
  browser otherwise connects for signalling but ICE never completes.
- Each `serve.sh` instance (one per board) listens on its own port, and the
  **dev host's** firewall has to allow every one of them, not just the first:
  a second board's page stays unreachable while the first board's still works,
  which reads like a producer problem but is a missing `ufw allow 8446/tcp`.