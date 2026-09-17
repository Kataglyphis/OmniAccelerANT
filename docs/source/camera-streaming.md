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
> As of 2026-09-17 the **native lane** sets
> `KATAGLYPHIS_RUST_FEATURES=gstreamer,onnxruntime_dynamic` by default — **not**
> `onnxruntime_directml`, which is a Windows-only execution provider — and the
> packaged artifacts carry their GStreamer/ONNX Runtime/model closure (below).
> `check-knt-abi.sh` runs in the lane.
>
> **No frame has actually reached the screen yet.** That needs a Linux desktop
> session and a camera; BACKLOG.md tracks it. Do not treat a green lane as a
> working camera.

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

### Relocatable Linux bundles

The native lane packages four formats from one bundle tree. Until 2026-09-17
that tree assumed the host had the image's GStreamer: the plugin DT_NEEDs seven
`libgst*` sonames, `bundle/lib` carried none of them, and the `.deb` declared
only `libc6, libstdc++6, libgtk-3-0`. The lane was green because the image's
ld.so cache has everything — which is exactly why no lane had caught it.

What travels in the bundle now (`scripts/linux/bundle-runtime-closure.sh`, run by
the lane for release builds, before packaging):

- **the GStreamer closure**, resolved from DT_NEEDED against pkg-config's
  `libdir` — never `ldd`, because the image also carries a distro GStreamer and
  `ldd` may pick that one — plus the pipeline plugins listed in
  `scripts/linux/lib/bundle-runtime.sh`;
- **ONNX Runtime** for the featured crate, plus the 59 MB detector model at
  `data/resources/models/yolov10m.onnx`;
- **an `$ORIGIN` rpath on every bundled ELF.** RUNPATH is not transitive: a
  dlopen'd plugin cannot reach a sibling through the runner's `$ORIGIN/lib`
  (measured), so "the file is present but unreachable" is the failure the gate
  rejects. The runner carries `$ORIGIN/lib:$ORIGIN/../lib` because the flatpak
  manifest installs the binary into `/app/bin` with the libraries in `/app/lib`.

At runtime the plugin's ELF constructor (`runtime_paths.cc`) points
`GST_PLUGIN_PATH`, `ORT_DYLIB_PATH` and `KATAGLYPHIS_ONNX_MODEL` at those
siblings — each only when the file exists and the environment does not already
name one, so a user override always wins.

`scripts/linux/check-bundle-closure.sh` grades the result headlessly — one
second, no display, no container-in-container: every DT_NEEDED of the runner and
of every bundle lib is bundled or in the documented system allowlist, every
bundled dependency is reachable through an `$ORIGIN`-relative RUNPATH, and the
pipeline plugins exist. A missing GStreamer lib fails the lane here instead of on
the first target machine. Both gates run in `run-native-linux.sh` after
`flutter build linux`.

The system allowlist is the GTK desktop stack the `.deb`'s `Depends` stand for.
It deliberately does not include GStreamer, ONNX Runtime or the camera stack —
those are the bundle's job.

Not covered by any of this: seeing a frame (BACKLOG.md, hardware-blocked), and
the `.deb` still naming only its GTK dependencies — correct now that GStreamer
travels, but it means the target is assumed to have a desktop stack.

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
can run side by side. In the **deployed shape every board serves its own
homepage**: producer on `:8443` and `serve.sh` + the web build on `:8444`, both
on the board — the dev host's `serve.sh` is for its own camera, or for an
ad-hoc look at another board via `--producer-host`.

The boards this repo has been deployed on:

| Board | Arch | Camera | Producer | Board-side quirks |
| --- | --- | --- | --- | --- |
| Raspberry Pi 5 | arm64 | imx219 (CSI) | Rust, inference | host-libcamera swap (rp1/pisp entity rename + libpisp 1.7) |
| Raspberry Pi Zero 2 W | arm64 | imx708 (CSI, mounted upside down) | `gst-launch`, no AI (512 MB) | host swap (vc4), `videoflip method=rotate-180` |
| Raspberry Pi 4 | arm64 | imx708 (CSI, mounted upside down) | Rust, inference | host swap (vc4), `/dev/dma_heap` ACLs, GCC 16 libs for ORT, `--rotate 180` |
| SpacemiT X100 | riscv64 | Logitech C270 (USB) | Rust, inference | no libcamera; camera ACL + udev rule, UFW `8443/8444` + UDP |

All four run the same `:latest-cross` (a multi-arch index) and the same web
build; the board-side pieces are the producer, `serve.sh` and nginx.

**Starting is one command, and deliberately not a service.** Nothing on a board
starts on boot; each board carries a small local `~/cat-cam.sh start|stop|status`
that brings up (or tears down) its producer and its nginx together and prints
the board's own URL. After a reboot that script is the whole procedure — there
are no systemd units on purpose.

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
(`meta="meta,name=Zero-Cat-Cam"`; a space fails to parse). For its own
homepage, install nginx on the board (`sudo apt install nginx`; it lands in
`/usr/sbin`, which is not on the user's `PATH`), open UFW (`8444/tcp` plus the
WebRTC UDP range), copy the web build and `serve.sh` over, and run it there:

```bash
# from the dev host (<board> is the target's ssh name)
rsync -a build/web/ <board>:cat-cam/build/web/
rsync -a scripts/linux/cat-stream/serve.sh \
  <board>:cat-cam/scripts/linux/cat-stream/serve.sh
# on the Zero (serve.sh derives its repo root from its own path, so the
# scripts/linux/cat-stream/ layout under ~/cat-cam is deliberate)
cd ~/cat-cam && PATH=/usr/sbin:$PATH bash scripts/linux/cat-stream/serve.sh
```

Media is WebRTC UDP, browser ↔ Zero, direct on the LAN. If the container is
too heavy for the board, `scripts/linux/cat-stream/package-producer-bundle.sh`
exports a container-less aarch64 bundle (producer + pruned GStreamer + the
image's glibc, ~180 MB) that runs against the host's libcamera with no
container and no toolchain; and `--no-inference` is the next step up from this
`gst-launch` bring-up.

**Other VC4/unicam Pis (e.g. Pi 4).** The same host-libcamera swap applies,
but the Rust producer fits there, and it needs **no board-specific runner**:
the Pi 5's runner works as-is — it collects the host libcamera closure, ACLs
`/dev/{video,media,dma_heap}*` (the dma_heap nodes matter here, or libcamera
reports `Could not open any dma-buf provider` and registration fails with
`-12`/ENOMEM) and puts `/opt/gcc-16.2.0/lib64` on `LD_LIBRARY_PATH`, which is
what the image's ONNX Runtime needs (`GLIBCXX_3.4.36 not found` otherwise).
The Pi 4's camera here is mounted upside down, so:

```bash
third_party/OxidANT/scripts/linux/cat-stream/run-producer-pi.sh --build --rotate 180
```

Its homepage works like the Zero's: nginx is preinstalled on Pi OS, `serve.sh`
runs with `PATH=/usr/sbin:$PATH` from a repo checkout (`~/OmniAccelerANT` here;
its board-local producer wrapper is `~/zweckle-producer.sh`).

**RISC-V SoC (SpacemiT X100).** `:latest-cross` is a multi-arch index
(amd64/arm64/riscv64), so the same tag runs there natively and the producer
builds inside the container in minutes on 8 cores — GStreamer, `v4l2src` and
ONNX Runtime are all riscv64 builds in the image. A USB webcam (e.g. a
Logitech C270) needs no libcamera: run with `--v4l2 /dev/videoN`. On Ubuntu
the host-level work is permissions and firewall: the node is `root:video 660`
and the user is usually not in `video`, so grant an ACL
(`sudo setfacl -m u:$USER:rw /dev/videoN`), and UFW needs `8443/tcp` plus the
WebRTC UDP range (`sudo ufw allow 32768:60999/udp`) because the browser
connects directly to the board for media. The udev rule keeps the ACL across a
re-plug (the C270 re-enumerates and a hand-set ACL dies with the old node):

```bash
printf 'SUBSYSTEM=="video4linux", RUN+="/usr/bin/setfacl -m u:%s:rw /dev/%%k"\n' "$USER" \
  | sudo tee /etc/udev/rules.d/99-catcam-acl.rules
sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=video4linux
```

For its own homepage: `sudo apt install nginx`, UFW `8444/tcp` plus the WebRTC
UDP range, then the same web-build + `serve.sh` copy as the Zero. Its
producer, from an OxidANT checkout carried over to `~/OxidANT` (`IMAGE` as
above):

```bash
# build once (model paths resolve because OxidANT is mounted at /workspace)
nerdctl run --rm --user 0:0 --network host -v "$HOME/OxidANT":/workspace \
  -v kataglyphis-cat-target:/cargo-target -v kataglyphis-cat-cargo:/cargo-home \
  -e CARGO_TARGET_DIR=/cargo-target -e CARGO_HOME=/cargo-home \
  --entrypoint bash "$IMAGE" -lc \
  'cd /workspace && cargo build --release --locked -p kataglyphis_cat_webrtc'

# run (detached; the board's wrapper is ~/x100-producer.sh)
nerdctl run -d --rm --name x100-producer --user 0:0 --privileged --network host \
  -v /dev:/dev -v "$HOME/OxidANT":/workspace \
  -v kataglyphis-cat-target:/cargo-target \
  -e ORT_DYLIB_PATH=/opt/opencv5/lib/libonnxruntime.so -e RUST_LOG=info \
  --entrypoint /cargo-target/release/kataglyphis_cat_webrtc "$IMAGE" \
  --v4l2 /dev/video9 --listen-port 8443 --name "Cat Cam"
```

If you front it from another host instead (`serve.sh --producer-host`), use its
**IP, not its mDNS name**: nginx resolves `proxy_pass` hostnames once at
startup, so a DHCP or mDNS address change leaves it proxying into the void with
a `101` in the access log and no connection on the producer.

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