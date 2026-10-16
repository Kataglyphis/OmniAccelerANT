# Camera Streaming

Practical WebRTC streaming and inference pipelines for Kataglyphis.

**The ObservANT in one minute.** A board with a camera runs the `omni-observant`
service, which finds the camera, looks for cats with a detection model and serves the web
app on port 8080.
- **Install:** `sudo dpkg -i omni-observant_<version>_<arch>.deb` on Debian or
  Raspberry Pi OS (amd64, arm64, riscv64). It starts at once and at every boot
  ([Installing it](#installing-it)).
- **Watch:** `http://<board>:8080/`. The Stream page plays the camera, says whether a cat
  is there, lists the visits with their pictures and videos, and shows the other ObservANT cameras
  ([The Stream page](#the-stream-page)).
- **Adjust:** the Camera page turns the picture, sets how sure detection must be, renames
  the camera and marks a spot as "not a cat" ([ObservANT package](#the-observant-package)).
- **Get told:** `notify_url` sends each arrival to a webhook; Home Assistant turns it into
  a phone notification with the picture and the video ([Home Assistant](#home-assistant)).
- **Check:** `/healthz` says whether the camera delivers, and what it saw
  ([Detection, visits and `/healthz`](#detection-visits-and-healthz)).
- **Configure:** `/etc/omni-accelerant/observant.toml` documents every setting you would
  change; what the page changes wins over it.

- [The detection model](#the-detection-model)
- [Measuring performance](#measuring-performance)
- [Rust-owned webcam inference (local, no WebRTC)](#rust-owned-webcam-inference-local-no-webrtc)
  - [Checking the knt ABI](#checking-the-knt-abi)
  - [Relocatable Linux bundles](#relocatable-linux-bundles)
- [WebRTC pipelines (Linux / web)](#webrtc-pipelines-linux--web)
  - [ObservANT package](#the-observant-package)
    - [Installing it](#installing-it)
    - [Cameras](#cameras)
    - [Detection, visits and /healthz](#detection-visits-and-healthz)
    - [Arrival picture, video and webhook](#arrival-picture-video-and-webhook)
    - [Home Assistant](#home-assistant)
    - [The Stream page](#the-stream-page)
    - [Tests](#tests)
    - [Where it ran](#where-it-ran)
  - [The Windows ObservANT](#the-windows-observant)
  - [Cat detection stream (Rust, native)](#cat-detection-stream-rust-native)
- [1) Start the signalling server](#1-start-the-signalling-server)
- [2) Export plugin path (if required)](#2-export-plugin-path-if-required)
- [3) Start a stream source](#3-start-a-stream-source)
  - [USB webcam](#usb-webcam)
  - [Pylon camera](#pylon-camera)
  - [Raspberry Pi (libcamera, example)](#raspberry-pi-libcamera-example)
- [4) Run the web frontend](#4-run-the-web-frontend)
- [Troubleshooting](#troubleshooting)

## The detection model

**DEIM-D-FINE-N, licensed Apache-2.0, fetched by checksum and never tracked** (owner,
2026-10-14). It replaced YOLO26n and YOLOv10m, both AGPL-3.0, which sat in AccelerANTgine's
and OxidANT's git trees. DEIM-D-FINE-N is DEIM's COCO checkpoint: 80 classes, 4 M
parameters, 7 GFLOPs, 43.0 AP, a 640x640 input and a 15 MB file.

- **Where it comes from.** [ModelANT](https://github.com/Kataglyphis/ModelANT) builds it
  from DEIM's pinned commit and checkpoint, exports it with its post-processing into the
  `[1, 300, 6]` layout the Rust parser already read (x1, y1, x2, y2, score, class) and
  releases it with its license and notice. Its preprocessing is a plain resize, which is the
  Rust default; the ONNX names it in its metadata (`kataglyphis.preprocess`).
- **How a build gets it.** `third_party/OxidANT/resources/models/models.lock` names each
  file with its URL and SHA-256. `third_party/OxidANT/scripts/linux/fetch-models.sh` puts
  them into `resources/models` (or `--dest DIR`) and fails on any other bytes, through a
  cache in `~/.cache/kataglyphis-models`. On Windows, `scripts\windows\Get-Models.ps1`
  does the same. The native lane, the Linux bundle, the ObservANT packages and OxidANT's
  Windows build all call it, so a fresh clone needs the network once. After that, run
  it once yourself before you start the app from a checkout.
- **What it changed on the boards.** Measured on 2026-10-14 against YOLO26n, with 2
  threads of ONNX Runtime on a Pi 5, over 12 arrival pictures from the three ObservANT
  cameras and one cat photo. It found the cats more often and more surely: a cat at the
  feeding trough went from 0.42 to 0.63, and a cat lying on the sofa, which YOLO26n missed, was
  found at 0.64. It found no new false cats. A run costs about 260 ms instead of 190 ms.
- **Another model.** Put it into ModelANT and move the lock's lines. For a one-off,
  `model = "..."` in `observant.toml` or `KATAGLYPHIS_ONNX_MODEL` names any `[1, N, 6]` ONNX
  file. The old models stay in the repositories' history; nothing was rewritten.

## Measuring performance

**The code's benchmarks live in each project's own tooling, and CI tracks them** (2026-10-14,
owner): a change that costs time shows in the run's summary. The yardstick is the **median** of
the default branch's last 20 runs on that arch, not the run before, so a slowdown that creeps in
a few per cent per commit still shows (2026-10-15). Above +25 % a run warns; a gated value at
more than double the median fails it, once 3 earlier runs exist. A shared runner is noisy, so
only stable values are gated, and a run the report failed never joins the history.

- **Rust:** OxidANT's Criterion benches under `cargo bench`, run by its Linux lanes: what a frame
  pays before the model, and a whole detection on the real model (OxidANT's AGENTS.md).
- **Flutter:** `integration_test/performance_test.dart`, driven in profile mode by
  `flutter drive --profile -d linux --driver=test_driver/perf_driver.dart
  --target=integration_test/performance_test.dart`. Flutter's `watchPerformance` times the
  frames of the app's start, three rounds through every tab, and resizes across both layout
  breakpoints; the driver keeps them in `out/perf/frontend.json`, and
  `scripts/linux/frontend-perf-report.py` turns them into the table (frames, build and raster
  time on average, at the 90th percentile and at worst, missed build budgets). The native lane
  runs it under Xvfb on x64 (`run_frontend_performance`); `reusable-linux.yml` keeps the
  default branch's last 20 results in `.perf-baseline/`. Gated: the average and the
  90th-percentile build time; the worst frame is one frame and only warns.

**When a frame is slow, find what it builds.** The report says *that* a scenario got slower; a
profile timeline says *where*. With an entry point outside the tree, say `build/probe/main.dart`,
that sets `debugProfileBuildsEnabled = true` (and `debugProfileBuildsEnabledUserWidgets`) before
calling the app's `main()`, run `flutter run --profile --trace-startup -d linux -t
build/probe/main.dart` under Xvfb, then
`python3 scripts/linux/flutter-trace-summary.py build/start_up_timeline.json`. It lists the
slowest UI and raster frames and the slowest UI frame's self time per event, which with that
flag is per widget. That is how the 2026-10-15 start-up fix was found: `StreamPage` held 938 ms
of a 963 ms build, because its `initState` enumerated cameras synchronously. Without the flag
the same command still splits a frame into BUILD, LAYOUT, PAINT, SEMANTICS and garbage
collection. A DevTools *Export timeline* file reads the same way.

**Two tools measure what the boards really do**, which no runner can: repeat them after a change
that could cost time there, and compare with the baseline below.

- `scripts/linux/observant/bench/model.sh PICTURE MODEL.onnx...`, on a board: the installed
  service runs each model nonstop on a still picture, on a spare port (no camera, no state, the
  live service untouched), and prints its time per run, runs per second, CPU and memory.
- `scripts/linux/observant/bench/viewer.sh BOARD [SECONDS]`, from another host: the API's
  response times, the service idle and while one phone-sized headless Chrome plays the stream,
  and that page's cold load: the files on the boot path with their times, the renderer the
  browser got, the first Flutter frame and the first video frame, and the requests and main-
  thread time once it runs, and when the signalling socket opened and answered.

**The baseline, 2026-10-14** (Pi 5 boards, the SpacemiT K3 board, the web client a headless
Chrome on a Pi 5):

| What | Pi 5 | SpacemiT K3 (riscv64) |
| --- | --- | --- |
| A model run in the service, DEIM-D-FINE-N / YOLO26n | 332 / 233 ms | 592 / 404 ms |
| The model alone at 1 / 2 / 4 threads (DEIM-D-FINE-N) | 420 / 258 / 265 ms | |
| Preprocessing, postprocessing per run | 3 ms, < 0.01 ms | |
| Per frame: I420 to RGBA, pixelation, motion thumbnail | 1.7, 0.7, 0.5 ms | |
| A snapshot JPEG | 10.7 ms | |
| The service idle, with one viewer (% of one core) | 3 to 4.5 %, 18 to 19 % | 1 %, 49 % |
| Memory idle, with one viewer | 180 to 190 MB, +30 MB | 245 MB, +27 MB |
| `/healthz`, `/snapshot.jpg` over the LAN | 0.3 to 4 ms, 0.3 to 19 ms | 3 ms, 38 ms |

The cold page is 4.9 MB in 105 to 112 requests: the renderer `skwasm_heavy.wasm` (2.2 MB)
and `main.dart.wasm` (1.5 MB) on the boot path, then six font files (0.5 MB), then the Rust
core (65 kB). The first Flutter frame came after 4.5 to 6.4 s on the board with Wi-Fi at
0.7 MB/s, the first video frame 3 to 3.5 s later. An open page then makes 48 requests a
minute and keeps the main thread 1.9 % busy.

What it says:
- **The model is 99 % of a detection.** Two threads are the fastest setting on a Pi 5; four
  are no faster.
- **Every viewer costs an encoder**: webrtcsink encodes once per viewer, about 15 % of a Pi 5
  core and half a K3 core each.
- **Plain HTTP costs 0.75 MB a visit.** Without a secure context the browser has no
  `ImageDecoder`, so Flutter loads `skwasm_heavy` (2.29 MB compressed) instead of `skwasm`
  (1.54 MB), and without cross-origin isolation it renders on one thread.

## Rust-owned webcam inference (local, no WebRTC)

On Windows the **Stream** page runs a fully local webcam → ONNX → texture pipeline
owned end-to-end by Rust — no signalling server, no browser. Video frames never
cross the Dart bridge; only detection metadata does.

> **Linux has the same design as of 2026-09-16; a frame has crossed it since 2026-10-05.**
> It is an *addition*: the WebRTC stream below stays, and a Linux build with
> no `KATAGLYPHIS_RUST_FEATURES` keeps the C++ GStreamer MethodChannel path
> exactly as it is. All four links are in the tree — the `knt_push_frame` C ABI,
> the feature forwarding, ONNX Runtime bundling, and the Dart branch behind a
> runtime `webcamInferenceAvailable()` probe: a compile-time answer, because
> `listCameras()` starts libcamera's device monitor. While the page probed with it,
> that held the app's first frame 0.94 s on a Pi 5 (2026-10-15); it is async now and
> runs only when someone asks for the camera list.
>
> As of 2026-09-17 the **native lane** sets
> `KATAGLYPHIS_RUST_FEATURES=gstreamer,onnxruntime_dynamic` by default — **not**
> `onnxruntime_directml`, which is a Windows-only execution provider — and the
> packaged artifacts carry their GStreamer/ONNX Runtime/model closure (below).
> `check-knt-abi.sh` runs in the lane.
>
> **A test-pattern frame reaches the texture on every native lane run.**
> `integration_test/webcam_frame_test.dart` starts `RustWebcamView` on
> `videotestsrc` under Xvfb and polls the plugin's `hasPushedFrame`, the flag
> `knt_push_frame` sets. A camera changes only the source, so the push path
> needs none. A green lane is still not a working *camera*: real V4L2 capture
> on Linux remains a manual check.

**Data flow:**

```
crates/media (gstreamer-rs)     src/webcam_engine.rs            src/api/webcam.rs (frb)
                                                              ┌ webcam_inference_available()
  mfvideosrc → ksvideosrc     ┌ pushes RGBA into the Flutter   │ list_cameras() (async)
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
  refusing any file that is not the image's chain build (AGENTS.md § 4, the
  ONNX Runtime bullet); DirectML execution provider with CPU fallback. Enabled by the crate features
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
GStreamer core DLLs into the runner. `mfvideosrc` comes from the image's own
GStreamer, which ANTfrastructure's
`windows/scripts/build/Build-GstreamerFromSource.ps1` builds with
`-Dgst-plugins-bad:mediafoundation=enabled`; it registers only on a Windows
client host (`platforms.md`, the `mediafoundation` row).

### Checking the knt ABI

`scripts/linux/check-knt-abi.sh` verifies the C ABI the Rust webcam engine
depends on: that `knt_api_version` and `knt_push_frame` are exported from the
built plugin, are callable from outside the library, and return their
documented error codes (`-1` bad arguments, `-2` unknown texture id). Its
Windows twin, `scripts/windows/Test-KntAbi.ps1`, loads the plugin DLL into
`pwsh` on the device: `windows-x64.yml` runs it on the host after the container
build, `windows-arm64.yml` on `windows-11-arm`.

It exists because that ABI is resolved **by name at runtime** with `libloading`.
A rename, a dropped export or a visibility change is not a compile error on
either side — the app builds, ships, and then silently never shows a frame. The
script `dlopen`s the plugin exactly as Rust does, so a failure here is a failure
Rust would also hit.

It does not, and cannot, check that a real frame reaches the screen: frames end
in a GTK texture. The native lane has a display since 2026-10-01 — it starts the
bundle and drives the integration test under the image's `xvfb-run` — and since
2026-10-05 `integration_test/webcam_frame_test.dart` pushes a test-pattern frame through
`knt_push_frame` there and polls the plugin's `hasPushedFrame`. A real camera's frame on
screen is still a manual check — on the Windows dev box that means the `usbipd attach
--wsl` route in AGENTS.md § 4.

Run it after a native build. The artefact is an ELF `.so`, so on a Windows host
it goes through a container, with the lane's build volume mounted:

```powershell
nerdctl run --rm --platform linux/amd64 `
  -v "C:\GitHub\OmniAccelerANT:/workspace" -w /workspace `
  --mount "type=volume,source=kataglyphis-lane-native-x64-workspace-build,target=/workspace/build" `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest `
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
- **ONNX Runtime** — the image's chain build and nothing else (owner rule
  2026-09-23): `libonnxruntime*` resolves only from `ORT_LIB_LOCATION`, else
  `/usr/local/lib/onnxruntime-cpu/lib`, and only once that directory's
  `libonnxruntime.so` proves to be the chain build — ORT embeds its source path
  through `__FILE__`, and the chain's is `/opt/onnxruntime/onnxruntime/core/`; the
  variable alone proves nothing. Never from the ld.so cache, where
  `/opt/opencv5/lib` carries a second copy that sorts first. It travels whether
  or not the Rust features ask for it, because `libAccelerANTgine.so` needs
  `libonnxruntime.so.1` either way. With the lane's features it is already
  there when the packer starts: `rust_builder/linux/CMakeLists.txt` stages both
  sonames from the same chain directory during `flutter build linux`. The packer
  then copies nothing for it and prints `Kept (already in bundle/lib, not
  copied)` with each file's sha256, so its `N file(s) copied` list never shows
  ORT in that case. Plus the 15 MB detector model at
  `data/resources/models/deim_dfine_n_coco.onnx`, with its license and notice, fetched
  and checked from OxidANT's `models.lock` ([The detection model](#the-detection-model))
  — the standard model, bundled by default (owner decision 2026-10-01); `KATAGLYPHIS_BUNDLE_MODEL=0` drops it for an
  artifact that then needs `KATAGLYPHIS_ONNX_MODEL` at run time;
- **an `$ORIGIN` rpath on every bundled ELF.** RUNPATH is not transitive: a
  dlopen'd plugin cannot reach a sibling through the runner's `$ORIGIN/lib`
  (measured), so "the file is present but unreachable" is the failure the gate
  rejects. The runner carries `$ORIGIN/lib:$ORIGIN/../lib` because the flatpak
  manifest installs the binary into `/app/bin` with the libraries in `/app/lib`.

At runtime the plugin's ELF constructor (`runtime_paths.cc`) points
`GST_PLUGIN_PATH`, `ORT_DYLIB_PATH` and `KATAGLYPHIS_ONNX_MODEL` at those
siblings — each only when the file exists and the environment does not already
name one, so a user override always wins. For ONNX Runtime that override must
still be a chain build: OxidANT's loader (`ort_runtime.rs`) refuses any file
without the chain's source path.

`scripts/linux/check-bundle-closure.sh` grades the result headlessly — one
second, no display, no container-in-container: every DT_NEEDED of the runner and
of every bundle lib is bundled or in the documented system allowlist, every
bundled dependency is reachable through an `$ORIGIN`-relative RUNPATH, the
pipeline plugins exist, and ANTfrastructure's G6 census
(`linux/scripts/06-packaging/check-ort-provenance.sh <bundle>`) finds every ONNX
Runtime binary in the bundle byte-identical to the image's chain ORT, and every
importer's ld.so lookup — RUNPATH, `$ORIGIN` expanded — landing on it. A
dlopen-only user such as `liboxidant.so` gets an `$ORIGIN` RUNPATH from the packer
for exactly that. `liboxidant.so` also holds the chain directory
`/opt/onnxruntime/onnxruntime/core/` as a string: OxidANT's loader checks the ORT
it loads for it. That makes it an importer, never an ORT build, but only to a
census that takes a whole NUL-terminated `__FILE__` source path as the ORT
fingerprint. A hub whose census still counts the bare directory reads the text
rustc packs before it as a relative build root and fails the correct bundle with
`UNPROVEN /lib/liboxidant.so` (run 35928030957, both arches). This repo's hub
pin has read whole paths only since e72a9a37 (2026-09-24), and
`test-check-bundle-closure.sh` carries the bytes around that string in the real
`liboxidant.so`. The census runs whenever a bundled file is ORT-named or names
the ORT ABI (`OrtGetApiBase` and G6's other markers), not only when a
`libonnxruntime*` file is present: an ORT user with nothing beside it, or an ORT
under another name, is exactly what G6's verdicts exist to refuse. What it does
not decide is which copy a process loads at run time — `runtime_paths.cc` above
points `ORT_DYLIB_PATH` at the bundled one. A missing GStreamer lib or a foreign ONNX Runtime
fails the lane here instead of on the first target machine. Both gates run in `lane-native-linux.sh` after
`flutter build linux`; `scripts/linux/tests/test-check-bundle-closure.sh`, which
mutation-tests when the census runs and that its verdict decides, runs in the
same lane's code-quality batch before the build.

The system allowlist is the GTK desktop stack the `.deb`'s `Depends` stand for.
It deliberately does not include GStreamer, ONNX Runtime or the camera stack —
those are the bundle's job.

Not covered by any of this: a frame from a real camera (the native lane pushes a
test-pattern frame through `knt_push_frame`, `integration_test/webcam_frame_test.dart`), and
the `.deb` still naming only its GTK dependencies — correct now that GStreamer
travels, but it means the target is assumed to have a desktop stack.

## WebRTC pipelines (Linux / web)

### The ObservANT package

#### Where it runs

The owner's cameras on the ObservANT package, as their `/healthz` reported them on 2026-10-15
(himbeergsaelzweckle on 2026-10-16).
Each serves its page on `http://<host>:8080/` (`http://himbeergsaelz.local:8080/` and so on), and
each keeps its own rotation in its `settings.json`: turn a camera with ⟲/⟳ on its own Stream page, and
the table's "turned" follows.

| Host | Board | Camera | Version | Updates | One detection |
| --- | --- | --- | --- | --- | --- |
| himbeere2 ("Cat Cam Büro") | Raspberry Pi 5, Debian 13 | imx219 (CSI), turned 180° | 2.1.0 | nightly, from the releases | 0.26 s |
| tabblscatcam ("Cat Cam Futtertrog") | Raspberry Pi 5, Debian 13 | Camera Module 3, imx708 (CSI), turned 270° | 2.1.0 | nightly, from the releases | 0.30 s |
| himbeerGsaelz (since 2026-10-15) | Raspberry Pi 3 Model B, Debian 13 | Camera Module 3 Wide, imx708_wide (CSI), turned 180° | 2.1.0 | nightly, from the releases | 2.05 s |
| himbeergsaelzweckle (since 2026-10-16) | Raspberry Pi 4 Model B (8 GB), Debian 13 | Camera Module 3 Wide, imx708_wide (CSI), turned 180° | 2.1.0 | nightly, from the releases, as a user install (no sudo) | 0.91 s |
| mintberrycrunch ("Mintberry Cat Cam") | SpacemiT K3 (riscv64), Ubuntu 26.04 | Logitech C270 (USB) | 2.1.0 | by hand: built on the board, since no release carries riscv64 | 0.59 s |

- **The first release reached a camera by itself.** v2.1.0 was published at 22:32 on
  2026-10-15; himbeere2's `omni-observant-update.service`, started by hand a minute later,
  downloaded its `.deb`, checked it against `SHA256SUMS` and installed it over 2.0.0, and the
  service came back with its 155 visits; a second run said "2.1.0 is up to date".
  tabblscatcam got it from its timer alone: at 03:37 on 2026-10-16 it found v2.1.0, checked
  the `.deb` against `SHA256SUMS`, installed it over 2.0.0, and the service came back with all
  224 visits.
- **himbeerGsaelz's config says `inference = "on"`.** A 1 GB Pi 3 reports 905 MiB, and 2.1.0's
  `auto` skips the model below 1024 MiB; the next release's `auto` takes 768 MiB (OxidANT
  5898e42), so a new Pi 3 detects without the setting. Its model runs at 2 s, about seven times
  the Pi 5's, but only while something moves.
- **himbeergsaelzweckle is a user install**, because no sudo password was at hand (*Without
  sudo* under *Installing it*). 2.1.0's tarball predates `--install --user`, so its `libexec/`
  scripts and `share/omni-observant/` units were the repository's, plus a `version` file. It runs
  like the others (30 fps, 7 % CPU, 216 MB), and its user timer took a local stand-in release
  "2.1.1" through `omni-observant-update.service` on 2026-10-16: checked, installed, restarted,
  rotation kept. The first real release to reach it will be the one after 2.1.0.
- A Pi Zero 2 W ran the earlier container shape, not this package, and so did a Pi 4 before
  himbeergsaelzweckle ([the board table](#cat-detection-stream-rust-native) under *Cat detection stream*).
- **A camera added or moved goes into this table**, with what its `/healthz` says.

**At a glance** (AGENTS.md § 2, until 2026-10-15):

`scripts/linux/observant/package-observant.sh` + `package/` — the installable
ObservANT (2026-10-05). It packs the producer, its GStreamer plugins, the chain
ORT (G6-proved), the model, the web build and the image's loader, glibc and
libstdc++ into `/opt/omni-observant`, and wraps that in a `.deb` and
an AppImage. The web build goes in without the `wimp` and `webparagraph`
renderers and the `*.symbols` maps, which no browser fetches from it (the script
stops if `flutter_bootstrap.js`'s load call ever asks for either), and the
producer's `--precompress` puts a zopfli `.gz` beside each file the server gzips
(2026-10-12). The `.deb` carries a systemd unit, enabled at install, and a ufw
profile. The AppImage's `--install` sets up the same through
`package/observant-install`, whose `setup` step the `.deb`'s `postinst` calls too.
**`/etc/omni-accelerant/observant.toml` is not a conffile, on purpose.** `setup`
writes it only when it is absent, `640 root:omni-observant`, since a `notify_url` can hold a
webhook secret, and takes other users' read off an older, world-readable one. As a conffile, an edited copy stopped the
next upgrade at dpkg's keep-or-replace prompt, which hangs over SSH. The unit is
sandboxed (`systemd-analyze security` 1.8, from 8.7); its comment names what stays open
for the camera, the RAM check and GStreamer's ORC, and the package test fails above 2.5.
It runs in `:latest`
with `--web-root` naming the web lane's `build/web`, **privileged**, because it also
builds a flatpak and `flatpak-builder` needs bubblewrap.
- The flatpak puts the same bundle in `/app/observant` on the image's freedesktop runtime.
- Its command is `package/flatpak-omni-observant`: a per-user `observant.toml`, and a sign-in
  autostart entry that `--autostart off|on` switches.
- It has no boot service and no Pi camera, since the sandbox cannot see `rpicam-vid`.
- `test-observant-package.sh` installs it system-wide as root, because a user install
  needs a D-Bus the container lacks.
- On riscv64 it builds the `.deb` and the tarball only, natively on the board in the
  riscv64 `:latest` (a 16 KiB-page Pi cannot emulate it): the freedesktop runtime has no
  riscv64 build and no AppImage runtime is staged for one. No CI lane builds it.

`package/*` is pinned to LF in `.gitattributes`, because those files land on the
target verbatim.
Detail: `docs/source/camera-streaming.md` § *The ObservANT package*.

`scripts/linux/observant/package-observant.sh` turns the producer below into one
installable service. Run it inside `:latest`, with the web lane's `build/web` as
its web root:

```bash
bash scripts/linux/observant/package-observant.sh --web-root build/web
# out/omni-observant_<version>_<deb-arch>.deb            Debian, Ubuntu, Raspberry Pi OS
# out/omni-observant-<version>-<uname-arch>.AppImage     any glibc distro
# out/omni-observant-<version>-<uname-arch>.flatpak      any flatpak desktop; USB cameras, sign-in start
# out/omni-observant-<version>-linux-<deb-arch>.tar.gz   the same bundle, unpacked
```

On riscv64 it writes the `.deb` and the tarball only: no freedesktop runtime and no AppImage
runtime exist for it.

The flatpak's `flatpak-builder` runs in bubblewrap, so the script needs a privileged
container (`nerdctl run --privileged`).

Install it with `sudo apt install ./omni-observant_<version>_<arch>.deb`,
or anywhere else with `sudo ./omni-observant-<version>-<arch>.AppImage --install`.
Then open `http://<host>:8080/` from any browser on the network.

Everything it serves is on that one port, plain HTTP:

| Path | Answers |
| --- | --- |
| `/` | the web app; its Stream page plays the camera and shows the cat's status, visits and last arrival |
| `/healthz` | JSON: `ok`, or `false` with the `problem`; the seconds since the last frame and model run (`frame_age_s`, `model_age_s`); the build (`version`), the browser tabs on the stream (`viewers`), the other ObservANT cameras (`peers`), the privacy filter (`privacy`: `off` or `pixelate`), whether the picture is too dark to detect anything (`dark`: the model then idles, and `ok` stays) and `stats`, sampled every 2 s: `capture_fps`, `model_ms` per run, `model_runs_per_s`, `cpu_percent` of one core, `cores`, `rss_mb`, `load_1m`, `temperature_c` and `uptime_s` (the CPU, memory, load and temperature from `/proc` and `/sys`, so `null` off Linux); the live camera, its `frame` size and rate, `model_runs`, `rotate`, `score`, and under `detection` the watched `in_view`, `last_seen`, `visits`, `last_score`, `recent` visits, the newest `clip`'s arrival and every kept one's (`clips`), and the `boxes` drawn now, as fractions of the picture |
| `/visits` | JSON: every visit of the last 30 days, newest first, as `[arrival, stay in seconds]` (`null` while still in view), and `days`; read by the Stream page's *Visits* panel, which counts them per day and per hour in the viewer's time zone (2026-10-15). Kept in `visits.json` beside `recent`, at most 10 000 visits; a file from before starts from its `recent` |
| `/snapshot.jpg` | the latest frame, boxes drawn; encoded once per frame however many ask |
| `/arrival.jpg` | the frame the last arrival was confirmed on; `?t=<arrival time>` that arrival's own, of the last five; `404` until a cat has come, or once that arrival's is dropped |
| `/arrival.mp4` | the last arrival as an H.264 clip, 3 s before it to 7 s after; `?t=<arrival time>` that arrival's own, of the last five; byte ranges answered; `404` until one is encoded, or once that arrival's is dropped |
| `/settings` | `GET`: the `name`, `rotate`, `score`, `ignore` and `classes` the settings page can change, and the `privacy` filter, which locks `classes`. `POST` any of them as JSON (`application/json` only), e.g. `{"rotate": 90}`: 0, 90, 180 or 270 degrees clockwise, a `score` from 0.05 to 0.95, a name of up to 64 characters, up to 16 spots marked "not a cat" as `[x1, y1, x2, y2]` fractions of the picture (`{"ignore": []}` forgets them), and the watched `classes`, one to all 80 COCO names (`{"classes": ["cat", "dog"]}`) |
| `/webrtc-ws` | the WebRTC signalling, forwarded to the producer's own server on loopback `:8443`; at most `max_viewers` tabs at once (8), `503` for one more; a tab that vanished without closing, a laptop asleep, frees its place within about 2.5 min (TCP keepalive, 2026-10-14) |

**Only ObservANT's own page may act** (2026-10-13). `/webrtc-ws` and a `POST /settings`
answer `403` when a browser's `Origin` is not the address the request was sent to, so
another site's page cannot open the camera or change it. A tool such as curl, which sends
no `Origin`, passes, and reads stay open to the other ObservANT cameras' pages.

**Every request must name the board by a local address** (2026-10-14): an IP, a name without
a dot, or one ending in `.local`, `.lan`, `.home`, `.internal`, `.home.arpa` or
`.fritz.box`, else `403`. Before, only acting requests were checked, so a website that pointed
a public name at the board (DNS rebinding) could read `/snapshot.jpg` and the clips as its
own. A reverse proxy under a public name is added to `allowed_hosts` in `observant.toml`.

**At most 128 connections at once, and a request head within 10 s** (2026-10-14). A device
that opens more, or holds sockets without sending, no longer uses up the service's files;
the 129th is closed unanswered until one frees.

**A model that keeps failing shows** (2026-10-14). After three failed runs in a row
`/healthz` says `ok: false` with `problem: "the model fails: …"`, so the Home Assistant
outage alert fires. Each failed run clears the drawn boxes, so none stays sharp under the
privacy filter, and the journal gets the first failure and then one line a minute.

**The Camera page changes ObservANT while it runs** (2026-10-13). It is the web app's
own page in the bottom bar, for a board that is easily moved or a spot with false alarms.
The Stream page carries the same ⟲ and ⟳ beside the camera's name (2026-10-16), so a
picture on its side is turned where it is seen; both post `{"rotate": …}` to `/settings`,
which the camera keeps in its `settings.json`, so every device keeps its own:
- ⟲ and ⟳ turn the picture a quarter each way. ObservANT turns it itself, before the
  model sees it, so detection, `/arrival.jpg` and the clips turn with the stream. The
  running capture follows on its next frame, with no restart and no reconnect. At 90 and
  270 the upright picture is bordered into the frame, black at its sides, instead of
  stretched: until then a quarter turn squeezed a 4:3 picture into 4:3 the other way round,
  and a cupboard looked square. A Pi camera turned a quarter (`rpicam-vid` or libcamera)
  captures at 480x360, which its ISP scales for free, so only the borders are added
  (2026-10-14): resampling the turned 480x640 cost a Pi 20 % of a core, the borders 3 %.
  Turning such a camera between landscape and portrait restarts its capture once, about a
  second; a USB webcam keeps its size and turns live.
- A slider sets the detection score, how sure the model must be before a cat counts. The
  next model run uses it. Higher means fewer false alarms, lower finds a cat in poor light.
  Under it the page names the last detection's score ("Last detection: 34 %"), real or
  false, so the slider can go just above a false one.
- **"Not a cat"** (2026-10-14) appears under the preview while a box is drawn. It marks the
  boxed spot, such as a drying rack, as no cat: from then on a detection that overlaps it
  by more than half (intersection over union 0.5) is dropped before it counts, is drawn or
  scores. A real cat in front of it still counts, since its box differs. The marked spots
  show grey over the preview, and "Watch again" forgets them all. Turning the picture
  forgets them too, as they no longer fit it.
- **"Recent detections"** (2026-10-14) lists the latest five arrivals with their pictures,
  each with "Not a cat", since a false one is seldom on screen when it happens: himbeere2's
  drying rack counted once at 09:09 for under three minutes. Each visit in `/healthz`'s
  `recent` keeps the `boxes` it arrived with, and the button adds those as ignored spots; one
  already ignored reads "Ignored". Visits from before that keep no boxes and are not listed.
- A field renames the camera. The next webhook event, `/healthz` and the web page (within
  5 s) carry the new name; the WebRTC stream's own name, which a GStreamer viewer shows, stays
  the one `observant.toml` gave it at start.
- A preview of `/snapshot.jpg`, reloaded every 3 s, shows the result, and a table what the
  camera runs: its sensor, frame size and rate, whether detection runs, the model's runs and
  the visits counted.

Each change is kept in the state directory (`settings.json`) and wins over the same key in
`observant.toml`, which the service cannot write; a key the page never set still follows the
file. `/settings` takes JSON only, so another site's page cannot change the camera with a
plain form post, and it checks a whole post before it applies any of it. On a page that is
not an ObservANT camera's own, the Camera page says no ObservANT answers.

**The web build ships compressed.** The packager runs the producer's `--precompress` over
its copy of the web build, so each file the server gzips has a zopfli `.gz` beside it:
about 5 % smaller than the server's own gzip, and nothing to compress on the board. A
first visit from a phone on the LAN is 4.46 MB on the wire, about 4.62 MB before
(himbeere2, 2026-10-12); over loopback it is 3.75 MB, 3.93 before. The gap is Flutter's
renderer: a plain-HTTP page at a LAN address is no secure context, so the browser offers
no `ImageDecoder` and the loader takes `skwasm_heavy` (2.2 MB gzipped, its own codecs
inside) over `skwasm` (1.5 MB). Only a certificate the phones trust would change that. The copy
leaves out what no browser fetches from this build: the `*.symbols` debug maps, and the
`wimp` and `webparagraph` renderers, which Flutter's loader fetches only when the
`_flutter.loader.load` call in `flutter_bootstrap.js` asks for them; the packager stops
if it ever does. The .deb is 88 MB, 81 MB before.

#### Installing it

**A new camera in five steps**, on a Raspberry Pi or any Debian or Ubuntu board (arm64 or amd64):

1. Flash the board, give it a name, and copy your SSH key to it
   (`ssh-copy-id <user>@<host>.local`). Attach the camera.
2. Fetch the newest release's package and check it, on the board:
   ```bash
   v=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/Kataglyphis/OmniAccelerANT/releases/latest | sed 's|.*/tag/v||')
   arch=$(dpkg --print-architecture)
   base=https://github.com/Kataglyphis/OmniAccelerANT/releases/download/v$v
   curl -fsSLO "$base/omni-observant_${v}_${arch}.deb" && curl -fsSLO "$base/SHA256SUMS"
   sha256sum --check --ignore-missing SHA256SUMS
   ```
3. `sudo apt install ./omni-observant_${v}_${arch}.deb`. The service starts, finds the
   camera by itself (`camera = "auto"`, below) and comes back after every reboot; the
   nightly update timer keeps it on the newest release from then on (*Updates from the
   releases*). With ufw on, `sudo ufw allow OmniObservANT`.
4. Open `http://<host>.local:8080/`. Turn the picture upright with ⟲/⟳ beside the camera's
   name on the Stream page (from the release after 2.1.0; on 2.1.0, on the Camera page),
   and name the camera on the Camera page. Each camera keeps both in its `settings.json`.
5. Add the camera to *Where it runs* above.

**Without sudo** (from the release after 2.1.0), the tarball beside the `.deb` installs for the
calling user instead of step 3. The user needs the `video` group, which Raspberry Pi OS and
Debian give the first user:

```bash
curl -fsSLO "$base/omni-observant-${v}-linux-${arch}.tar.gz"
sha256sum --check --ignore-missing SHA256SUMS
tar -xzf "omni-observant-${v}-linux-${arch}.tar.gz"
./omni-observant/observant --install --user
```

It copies the bundle to `~/.local/opt/omni-observant` and sets up `omni-observant.service` and
the nightly `omni-observant-update.timer` under the user's systemd, with linger, so both start at
boot without a login. The settings are the user's own `~/.config/omni-observant/observant.toml`
(mode 600), the visits and `settings.json` live in `~/.local/state/omni-observant/`.
`--no-autostart` and `~/.local/opt/omni-observant/observant --uninstall --user [--purge]` work as
for the system install. It refuses root, and refuses beside a system-wide install, since both
would serve port 8080. Moving to the `.deb` later: `--uninstall --user`, step 3, and copy
`settings.json` and `visits.json` to `/var/lib/omni-observant/` (owner `omni-observant`).

**The AppImage either runs or installs.** Started plainly, it runs ObservANT in the
foreground as the calling user, which needs the `video` group. `--install` copies it
to `/opt/omni-observant` and sets up the same service as the .deb:
- the unit goes to `/etc/systemd/system`, and `omni-observant` to `/usr/local/bin`;
- `--no-autostart` leaves the service disabled;
- running it again with a newer AppImage upgrades, keeping the settings and the
  enabled or disabled state;
- `omni-observant --uninstall [--purge]` removes it;
- `--install --user` installs for the calling user instead, with no root (*Without sudo* above).

The installer is `libexec/observant-install` in the bundle, so the tarball's
`sudo ./observant --install` does the same. It refuses while the .deb is installed,
and the .deb's `postinst` uses it to create the user. Without FUSE, set
`APPIMAGE_EXTRACT_AND_RUN=1`.

**The flatpak starts at sign-in, not at boot, and takes USB cameras only.** Install it
with `flatpak install ./omni-observant-<version>-<arch>.flatpak`; a desktop
without the freedesktop runtime it names fetches that from Flathub. Start it with
`flatpak run org.kataglyphis.omni-observant`.
- It runs the same bundle, from `/app/observant`, in a sandbox that has the network, every
  device (`--device=all`, as the app's flatpak has) and the host's `~/.config/autostart`.
- Its first run seeds `~/.var/app/org.kataglyphis.omni-observant/config/omni-accelerant/observant.toml`
  from the template and writes the sign-in entry. `flatpak run --command=omni-observant
  org.kataglyphis.omni-observant --autostart off|on` switches it.
- A flatpak cannot carry a systemd unit, so it starts when the user who ran it once
  signs in, never at boot.
- It cannot use a Raspberry Pi camera. `rpicam-vid` is a host tool the sandbox cannot see,
  and the image's libcamera cannot drive a Pi 5. On a Pi, use the .deb or the AppImage.

**What the bundle carries.** Everything lives in `/opt/omni-observant`:
- the producer;
- the GStreamer plugins it uses (`rswebrtc` and its WebRTC/DTLS/SRTP stack
  included), and NSS's crypto modules beside `libnss3`;
- the image's chain ONNX Runtime, proved by the hub's G6 census before packaging;
- `deim_dfine_n_coco.onnx` (Apache-2.0; its license and notice in `share/doc/omni-observant/`);
- the web build;
- the image's own loader, glibc and GCC 16 `libstdc++`. The chain ORT needs
  `GLIBC_2.43` and `GLIBCXX_3.4.36`, which no current distro ships.

The `observant` launcher runs the producer through that loader with
`--library-path`, never `LD_LIBRARY_PATH`. A child it starts, such as the host's
`rpicam-vid`, therefore keeps the host's libraries. libcamera is the one library
left to the host, because its IPA and tuning files must match the host kernel.

**What the .deb does on install.**
- It creates the `omni-observant` system user and adds it to `video` and `render`.
- It enables and starts `omni-observant.service`, so ObservANT comes back after a
  reboot, and after any exit of its own (`Restart=always`). The unit starts after
  `time-sync.target`, so on a board without a clock, where a time-wait-sync service is
  enabled, the first visit is not stamped with yesterday's time.
  - `systemctl disable --now omni-observant` turns that off, and upgrades keep the
    choice.
  - `OMNI_OBSERVANT_AUTOSTART=0` on the first install leaves the service disabled.
- `/etc/omni-accelerant/observant.toml` is written at the first install, with every
  setting commented out, and never overwritten. `omni-observant --print-config`
  shows the settings in effect.
  - Only root and the service's group read it (`640 root:omni-observant`), because a
    `notify_url` can carry a webhook's secret. An install before 2026-10-13 wrote it
    world-readable; the next upgrade takes that read away and keeps its content.
  - It is deliberately not a conffile. dpkg asks about an edited conffile on every
    upgrade that changes it, and over SSH or in an unattended upgrade nobody
    answers, so the install hangs. Found on himbeere2, 2026-10-05.
  - `apt purge` removes it.
- `sudo ufw allow OmniObservANT` opens `8080/tcp` and the WebRTC range
  `40000:40099/udp`.

#### Cameras

**How it picks a camera** (`camera = "auto"`), in this order:
1. A Raspberry Pi camera through the host's `rpicam-vid`. The image's libcamera
   cannot drive a Pi 5, which is why the host tool goes first.
2. `libcamerasrc`.
3. A USB webcam (`uvcvideo`), MJPEG when it offers no raw format.
4. A test pattern as a stand-in, which re-probes every 30 s, so a camera plugged
   in later is picked up.

#### Detection, visits and `/healthz`

`/healthz` reports which camera is live and the cat: whether one is in view, when one
was last seen (Unix seconds), how many visits it counted, the last best score, and the
latest 20 visits, newest first (`recent`: `arrived`, and `stayed_s` once the cat has
left).
**`ok` is `false` when the camera does not deliver** (2026-10-13), and `problem` says why:
"waiting for the first frame", "no frame for 25 s" after 20 s without one, or "no camera
found, streaming a test pattern". Until then `ok` was always `true`, so a monitor saw a
ObservANT whose camera had gone as healthy. `frame_age_s` and `model_age_s` are the seconds
since the last frame and the last model run. The Stream page and the Camera page show the
problem in orange above the cat.
`/snapshot.jpg` is the latest frame, boxes included, for a quick look without
WebRTC: `curl -o cat.jpg http://<host>:8080/snapshot.jpg`. A cat counts after two
detections in a row and is out of view after about 3 s without one, so a lone hit near the
score threshold draws no box and logs nothing. Its visit ends a minute after its last
sighting (2026-10-14): a cat back sooner, from behind the sofa or the feeding bowl, continues
the visit and is not announced again. At the feeding trough one cat walking about had made
21 visits in an hour, 10 to 90 s apart; the departure event and `stayed_s` come a minute
later now, and `stayed_s` counts from the first sighting to the last.

While nothing moves and no cat is in
sight the model runs only every 5 s (`idle_inference_fps`), and not at all while the
picture is black; motion brings back `inference_fps`, and `/healthz` counts the
runs (`model_runs`). On a Pi 5 that took a still, empty scene from 74 % to 12 % of a
core, and a dark room at night to 2 %. A cat in view that does not move, asleep or a false
one, is looked at half as often (2026-10-13): himbeere2's drying rack, counted as a cat at
0.34 all afternoon, went from 69 % to 36 % of a core. Leaving is motion, so the cat is
out of view as fast as before. `inference = "auto"` turns the model
off below 768 MiB of RAM: a 512 MB Pi Zero 2 W reports about 430 MiB, a 1 GB Pi 3 905 MiB. It
was 1 GiB until 2026-10-15, which kept the Pi 3 from detecting at all.

**A cat must move to arrive** (2026-10-14). A detection starts a visit only where the picture
changed in the last 10 s, in at least two 8-pixel blocks inside its box or one block around it: a still object the
model takes for a cat, like himbeere2's drying rack (92 "visits" by 13:40 on 2026-10-13),
can no longer start one. Once a cat is in view, every detection keeps its visit going, so a
cat that sits down or falls asleep stays counted. What the camera sees as it starts counts
as just arrived, so a cat already there when the service starts is counted then. The motion
comes from the same 2 Hz looks that pace the model; with that pacing off
(`idle_inference_fps` at or above `inference_fps`, or `inference_fps = 0`), every detection
may start a visit, as before.

A live `/healthz` from himbeere2 (2026-10-14), its lists cut to two entries each and the
peers' addresses left out:

```json
{
  "camera": "Raspberry Pi camera via rpicam-vid (imx219 [3280x2464 10-bit RGGB] (...))",
  "detection": {
    "boxes": [],
    "clip": 1791965878,
    "clips": [1791965878, 1791961744],
    "in_view": false,
    "last_score": 0.6694751977920532,
    "last_seen": 1791965880,
    "recent": [
      { "arrived": 1791965878, "boxes": [[0.001, 0.693, 0.608, 1.0]], "stayed_s": 0 },
      { "arrived": 1791961744, "stayed_s": 172 }
    ],
    "visits": 154
  },
  "frame": { "fps": 30, "height": 480, "width": 640 },
  "frame_age_s": 0,
  "inference": true,
  "model_age_s": 0,
  "model_runs": 2146,
  "name": "Cat Cam Büro",
  "ok": true,
  "peers": ["http://<other-cat-cam>:8080", "http://<third-cat-cam>:8080"],
  "problem": null,
  "rotate": 180,
  "score": 0.25,
  "version": "2.0.0 (b8e1ee5)",
  "viewers": 0
}
```

Before the first cat, `last_score`, `last_seen` and `clip` are `null`, and `clips` and
`recent` are empty.

`model_runs` counts since the service started. `visits`, `last_seen`, `last_score` and
`recent` survive a restart, and so does `/arrival.jpg`: the service keeps them in
`/var/lib/omni-observant`, its systemd state directory, on every arrival and
departure and once more when it stops. A visit the stop cut short is closed at the cat's
last sighting when the service starts again; after a power cut, which writes nothing, at
the last arrival or departure written. The flatpak keeps them in its own `~/.var/app/…/.local/state`, the Windows
ObservANT in `%LOCALAPPDATA%\omni-observant`. `last_seen` and `last_score` stay `null` until a cat has been in view.

The Stream page reads the same `/healthz` every 5 s while it shows, and at once when it
comes back from another tab (`CatStatusLine` in
`lib/Pages/StreamPage/cat_status.dart`): under the video it puts ObservANT's `name`,
then "Cat in view", "Cat last seen: 14:32" or "No cat seen yet", in English or German,
the three latest visits ("Recent visits: 14:32 (3 min) · 11:05 (10 min)"; one still going
on has no stay yet), and from the first visit on the last arrival's picture. Its URL carries the visit count
(`/arrival.jpg?visit=3`), not `last_seen`, which moves on every model run while a cat
stays, so the page fetches the picture once per visit. On the photo, with the cat in
view for 35 s, headless Chrome sent seven `/healthz` requests and one `/arrival.jpg`
(2026-10-12). Served from anywhere else, where `/healthz` is no ObservANT's answer, it
shows only the title.

Since 2026-10-14 the page also:
- says "Camera unreachable since 14:32" in orange once an ObservANT camera that answered stops
  answering, and keeps what it said last, its name, visits and picture;
- folds out the whole visit log ("All 20 visits") under the three latest;
- shows each earlier video with its arrival's picture (`/arrival.jpg?t=`), so the right
  one is found at a glance;
- **closes the video in a tab hidden for a minute.** ObservANT encodes for each viewer,
  so a forgotten tab cost a core's share all night; a glance at another tab keeps the
  picture, and showing the tab again opens a new session at once.

**A tab you come back to plays again** (2026-10-14). The owner's old tab stayed on "Der
Videostream wird ausgehandelt" while a new one played. After a laptop sleeps or the Wi-Fi
changes, the browser can hold a signalling socket that looks open and carries nothing;
gstwebrtc-api reconnects only on a close event, which never came, so the page asked a dead
socket for a stream. Reproduced in headless Chrome through a proxy that silences the
page's open connections and keeps new ones working. Three guards now:
- a tab that was hidden long enough to close its session rebuilds the signalling
  connection when it shows again, before it asks for a stream;
- a session that gets no answer within 15 s rebuilds it too;
- a picture whose decoded-frame count stands still for 10 s while streaming in a visible
  tab (the camera restarted behind the dead socket) closes the session and rebuilds it.

  The cat line's and the overview's requests give up after 8 s, so one on a dead connection
  no longer waits for minutes. Measured: back after 75 s with the socket silenced, the video
  played again within 3 s; with the service restarted after the return, 9 s after it.

**An overview of the other ObservANT cameras** (2026-10-14). List them in `observant.toml` as
`peers`, each one's origin, on every ObservANT:

```toml
peers = ["http://192.168.1.51:8080", "http://192.168.1.45:8080"]
```

The Stream page then shows a card per peer under its own cat: the peer's name, a picture
refreshed every 10 s, and its cat line, or "Not reachable"; a tap opens that ObservANT's
page. A peer answers this page's reads (`/healthz`, `/snapshot.jpg`, `/arrival.jpg`,
`/arrival.mp4`) with `Access-Control-Allow-Origin` and `Cross-Origin-Resource-Policy:
cross-origin` only when it lists this page's origin among its own `peers`; nothing else,
and no page outside the list, gets those headers. So list them both ways, and by the
address the browser uses.

#### Arrival picture, video and webhook

**It can tell you ObservANTe.** Set `notify_url` in `observant.toml` and the service
POSTs a JSON event there whenever a cat arrives or leaves:

```json
{"event": "arrived", "name": "ObservANT", "time": 1791763273, "class": "cat",
 "detections": 2, "best_score": 0.76, "snapshot": "/arrival.jpg"}
{"event": "clip", "name": "ObservANT", "time": 1791763273,
 "best_score": 0.76, "clip": "/arrival.mp4", "snapshot": "/arrival.jpg"}
{"event": "left", "name": "ObservANT", "time": 1791763375, "stayed_s": 42,
 "arrived": 1791763273, "best_score": 0.76}
```

The departure is posted a minute after the cat was last seen, so its `time` lies that much
after `arrived` plus `stayed_s`.

`/arrival.jpg` is the frame the arrival was confirmed on, boxes included, so a
notification can show what triggered it. Each of the last five arrivals keeps its own,
`/arrival.jpg?t=<time>` (2026-10-13), as the clips do: until then a false visit a minute
later replaced the picture a cat's notification showed. A Home Assistant webhook trigger takes the events
as they are: its URL `http://<home-assistant>:8123/api/webhook/<id>` is the
`notify_url`, and `trigger.json.event` tells arrival from departure. https works too.
Deliveries run on a thread of their own with a 5 s timeout. A failed one is tried again
after 5 s, 15 s, 45 s and 2 min, so a Home Assistant restart loses no visit; the events
stay in order, and one older than ten minutes is dropped, since a notification that late
helps nobody. The log names only the URL's scheme and host, because a webhook's path is
often its secret.

**Each arrival is a 10 s video too.** The capture thread hands every annotated frame to
`clip.rs`, which keeps one in three (10 fps of the 30) for the last 3 s, as buffer
references, so nothing is copied. An arrival takes those and the next 7 s and gives them to
a thread of its own, which encodes them with `openh264enc` at 800 kbit/s (about 1 MB a
clip at 640x480), `h264parse` and `mp4mux faststart=true`, so the index comes first and a
browser starts playing at once. `/arrival.mp4` serves it with byte ranges, which Safari's
`<video>` needs; `/healthz` names the newest one's arrival as `detection.clip`; and `notify_url`
gets a `clip` event once it is written, with the arrival's `time` and `best_score`.
A second arrival during a clip's 7 s gets a clip of its own (2026-10-13): up to three
record at once and share their frames, and two finished ones wait for the encoder.
**The last five clips stay addressable by arrival**, as `clip-<time>.mp4` in the state
directory, across a restart too: `/arrival.mp4?t=<time>` serves that arrival's own, and
`404` once it is dropped, never a newer one. A false visit right after the cat (33 of them
on himbeere2's morning of 2026-10-12) would otherwise have put its clip behind the cat's
notification. The arrival event carries the visit log's own time, the one the clip is kept
under. The Stream page links the newest clip by its time once `detection.clip` is the newest
visit, so it never offers the previous cat's clip, and lists the other kept ones beside it
("Earlier videos: ▶ 18:07 ▶ 18:05", from `detection.clips`).
On himbeere2 the packaged service, run on the cat photo at 30 fps (2026-10-12), confirmed
the arrival at 16:21:40 and served the clip at 16:21:47: seven seconds of post-roll, and
encoding and writing in under one. It was H.264 Constrained Baseline, which every phone
and browser plays, 640x480 at 10 fps, 78 frames (the pre-roll was short, as the instance
had just started) and 603 kB; `/arrival.mp4` answered `Range: bytes=0-99` with `206`.
With its own camera that evening (18:03 to 18:08) six arrivals of the drying rack at the
bottom of the frame made one clip each, the full 100 frames, of 108 to 182 kB: a still
room compresses far below the bitrate's ceiling. Memory plateaus rather than grows: forty
100-frame 640x480 encodes in a row (a release build, 0.6 s each) held the process at
70 MB from the sixth on, glibc keeping the freed frames for the next clip, and the live
service sat at 282 MB for 20 minutes after fourteen arrivals, that plateau plus the
model's.
`clip_seconds` sets the length (0 records none). Frames wait in memory until encoded,
about 46 MB for 10 s, which is why the setting stops at 60. The package bundles `isomp4`
for `mp4mux` (`openh264` and `videoparsersbad` were in it already); a GStreamer without
one of the three records no clip and says which at start. `test-observant-package.sh`
checks that the photo's arrival yields one, that it is an MP4 that answers a byte range,
that its event reaches the webhook, and that a restart keeps it.

#### Home Assistant

**A phone notification with the picture, through Home Assistant.** This automation sends
an arrival to the Home Assistant companion app, with `/arrival.jpg` as its image and the
live page behind a tap. Running on himbeere2 since 2026-10-12 (Home Assistant 2026.10.1):

```yaml
# automations.yaml; both values live in secrets.yaml, so this file can be committed.
- id: catcam_arrival_notification
  alias: Katze ist da (Cat Cam)
  mode: parallel        # the clip's update must not wait behind the arrival's run
  triggers:
    - trigger: webhook
      webhook_id: !secret catcam_webhook_id   # notify_url ends in this
      allowed_methods: [POST]
      local_only: true
  variables:
    catcam: !secret catcam_base_url           # e.g. http://<cat-cam-host>:8080
    video: "{{ trigger.json.event == 'clip' }}"
  conditions:
    - condition: template
      value_template: >-
        {{ trigger.json.event in ['arrived', 'clip']
           and (trigger.json.best_score | float(0)) >= 0.45 }}
  actions:
    # The arrival sends the picture; its clip, some seconds later, updates the same notification.
    - action: notify.mobile_app_<phone>
      data:
        title: "🐱 Katze ist da"
        message: >-
          {{ trigger.json.name }}: um
          {{ trigger.json.time | timestamp_custom('%H:%M') }} gesehen,
          {{ ((trigger.json.best_score | float(0)) * 100) | round(0) | int }} % sicher.
        data:
          image: "{{ catcam }}/arrival.jpg?t={{ trigger.json.time }}"
          clickAction: >-
            {{ catcam ~ ('/arrival.mp4?t=' ~ trigger.json.time if video else '/') }}
          tag: catcam-arrival
          alert_once: true
```

- **A webhook id is a password.** Generate it (`python3 -c 'import secrets;
  print("catcam-" + secrets.token_urlsafe(24))'`) and keep it out of git.
- **Notify above 0.45, count from `score`.** On 2026-10-12 a white object at the bottom of
  himbeere2's frame made 33 "visits" between 0.26 and 0.44, and a real cat at the feeding
  trough scored 0.72 (2026-10-14). The condition keeps those off the phone while the visit log still counts
  them; raising `score` instead would drop them from both. It is not enough on its own:
  at 21:57 the same object scored 0.65 and reached the phone (BACKLOG, *False arrivals*).
  For a spot like that, raise that one camera's `score` above the false object's on the
  web app's Camera page (since 2026-10-13): it applies at the next model run, needs no
  SSH, and leaves the other cameras as they are.
- **The companion app's `minimal` build has no push service.** It receives notifications
  only over its own connection to Home Assistant, so set *Persistent connection* to
  *Always* in its server settings. The `full` build gets them through Firebase. A push
  while the app is not connected fails with `not connected to local push notifications`
  and is gone; himbeere2's automations therefore send each notification three times a
  minute apart under one `tag` with `alert_once: true`, and `continue_on_error` on the call,
  so a repeat replaces a delivered one silently and reaches a phone that reconnected.
  Each run then lasts about two minutes, so give `mode: parallel` a `max` well above its
  default of 10: on the morning of 2026-10-14 three cameras' arrivals, clips and departures
  overran it and Home Assistant dropped 30 events (`Maximum number of runs exceeded`),
  their counts included. himbeere2 runs `max: 40`.
- **The picture loads from the phone,** so `catcam_base_url` must be an address the phone
  can reach: an IP or a name its network resolves, not loopback.

A test arrival posted to that webhook reached the owner's phone on 2026-10-12.

**The same notification learns when the cat left.** The departure comes a minute after
the cat was last seen, since a cat back sooner continues its visit. It names the arrival it
ends (`arrived`) and that arrival's `best_score`, so an automation that lets `left` through
its condition too (himbeere2's does; the one above does not) takes it under the same 0.45
and updates the notification by its `tag`: "Katze war da … War 4 Min. da." A clip event
carries `stayed_s` too when the visit was over before its clip was encoded; with a visit
lasting a minute past the last sighting and a clip of at most 60 s, that hardly happens.
himbeere2's automation keeps the last departure in an `input_text`
(`"<arrival time> <seconds>"`), so its minute-apart tries of an arrival keep the stay a
departure in between added.

**At 21:00 a summary.** Each notified arrival appends its time to another `input_text`,
which the midnight reset clears with the day's counter, and a time trigger sends
"Heute 2 Katzenbesuche: 07:12, 18:30." or "Heute keine Katze gesehen." under a tag of its
own.

**More than one ObservANT.** Each posts to a webhook of its own, and one automation takes
them all: a webhook trigger per camera with an `id`, and variables that map that id to
the camera's base URL (both in `secrets.yaml`), its video sensor and the place a
notification names ("Katze ist am Futtertrog"). The `tag` carries the id
(`catcam-arrival-<id>`), so one camera's notification never replaces another's, and the
stay is kept as `"<id> <arrival> <seconds>"`. The counters count both, and the summary
names the place with each time ("21:57 Büro, 22:30 Futtertrog"). A second `rest` entry
polls the other camera's `/healthz`, and the outage alert watches both online sensors,
under one tag per camera. Since 2026-10-12 himbeere2's Home Assistant takes its own cat
cam ("Cat Cam Büro", on loopback) and tabblscatcam's ("Cat Cam Futtertrog", a second
Pi 5 with a Camera Module 3); a departure posted from tabblscatcam to its webhook updated
that camera's notification and stay.

**Statistics and an outage alert, from `/healthz`.** Home Assistant's `rest` integration
polls `http://127.0.0.1:8080/healthz` every 30 s when it runs on ObservANT's host:
`detection.in_view`, `detection.last_seen`, `detection.visits`, `detection.recent[0].stayed_s` and `ok` become
sensors, and with ObservANT unreachable they all turn `unavailable`. On himbeere2
(2026-10-12):
- the arrival automation increments two counters, *today* and *total*, so they count only
  what reached the phone; a template sensor with `state_class: total_increasing` mirrors
  *total*, which lets a `statistics-graph` card draw visits per day, and a time trigger
  resets *today* at midnight;
- `binary_sensor.cat_cam_online` unavailable or off for five minutes sends "ObservANT
  offline", and its return after such an outage sends "ObservANT wieder da"; a Home
  Assistant restart's few seconds stay quiet. Stopping `omni-observant` for 5 min 45 s sent
  the first at 5 min, on the dot.
- **Off and unavailable say different things** (2026-10-14). Since `/healthz` reports
  `ok: false` for a camera without a picture, the online sensor is off while ObservANT
  answers but sees nothing, and unavailable only when it does not answer. A sensor per
  camera keeps the reason, and the alert names it: "hat seit 5 Minuten kein Bild (no frame
  for 300 s)" for the first, "antwortet seit 5 Minuten nicht" for the second.

  ```yaml
      sensor:
        - name: ObservANT Problem
          unique_id: catcam_problem
          icon: mdi:camera-off
          value_template: "{{ value_json.problem or 'ok' }}"
  ```
- **A sensor that has no value yet needs `availability`, not `none`.** A `rest` template
  that returns `none` renders the text "None", which a timestamp sensor logs as an invalid
  timestamp on every poll and a duration sensor refuses at load (`ValueError: ... has the
  non-numeric value: 'None'`). A new camera has no sighting yet, and a visit in progress
  has a null `stayed_s`, so `last_seen` and the stay are guarded with `availability`
  templates (`{{ value_json.detection.last_seen is number }}`) and show unavailable instead.

#### The Stream page

**An open page survives a restart of the service.** The page sees its producer go and
come back and consumes the new one, with no reload: on himbeere2 (2026-10-12) headless
Chrome's video was playing at 30 fps again about 10 s after `systemctl restart
omni-observant`, as an upgrade does it.

**A language or theme change keeps the picture.** Either remounts the video box, and the
stream's state lives outside it: one `WebRTCStreamController` per page load
(`lib/Pages/StreamPage/stream_controller.dart`) registers the signalling listeners once.
A remounted view attaches to the session as it was. A view that comes back after the
session's 30 s keep-alive opens a new one at once from the producers the client already
knows, because gstwebrtc-api never repeats a `connected` or `producerAdded` that has
fired. A failed session is retried after 3 s. In headless Chrome on a test pattern
(2026-10-12) the video kept counting about 33 frames a second through a switch to English
and back, a theme toggle and two page changes. Before, a language switch left the box at
"Connecting to the signalling server".

**What a browser downloads** (measured on himbeere2, 2026-10-14, Chrome 154 on the LAN):
the first visit 4.5 MB in about 60 requests, the video playing after 3.6 s; every later
visit 0.11 MB, the video after 2.9 s, because the server answers each file with an ETag and
`Cache-Control: no-cache`, and an unchanged one costs a `304` without a body. Half of the
first visit is Flutter's renderer, `skwasm_heavy.wasm` (2.2 MB gzipped): Flutter takes the
heavy one when the browser has no native image decoder, and Chrome offers WebCodecs'
`ImageDecoder` only in a secure context, which plain HTTP on a LAN address is not. So over
`http://<board>:8080` every browser gets it; served over HTTPS or from `localhost`, Chrome
would take the lighter `skwasm.wasm`. The app itself, `main.dart.wasm`, is 1.5 MB, and
the six Roboto files about 0.5 MB.

**One port reaches it.** The page and the `/webrtc-ws` signalling share `:8080`:
the service forwards the WebSocket upgrade to its own signalling server on
loopback `:8443`. Media goes over host candidates only unless `stun_server` is
set, so the stream stays on the LAN. No TLS, no `serve.sh`, no container.

#### What it detects

**Cats by default, any of the 80 COCO classes on request** (2026-10-14). `classes` in
`observant.toml` names them (`["cat"]` unless set), and the Camera page's "What it detects"
adds one from a menu that filters as you type, or removes one by its chip; the last cannot
go. A change applies at the next model run and stays across restarts. Everything that
counts a cat counts any of them: visits, the webhook events, the arrival photos and clips,
the boxes. Each visit in `/healthz`'s `recent` and each `arrived` event names its `class`,
the class of its best detection; `/healthz` lists `classes`. `all_classes = true` still counts
every class. The privacy filter keeps every watched class sharp, so watching `person` shows
people. While it is on, only `observant.toml` sets the classes: the Camera page shows them
without the editor, `POST /settings` refuses other ones, and classes a page saved earlier
give way at the next start (2026-10-14).

#### Stats for developers

**A "Stats" button under the camera's name** (2026-10-14) opens a panel that refreshes every
2 s while open: what ObservANT delivers and costs (`/healthz`'s `stats`: frames per second
against the configured rate, the model's time per run and runs per second, its CPU share of
one core, the cores, memory, the 1-minute load, the board's temperature, how long it has
run, the viewers) and what this browser makes of the stream (frames per second received,
the picture's size, frames dropped so far). Closed, it polls nothing.

#### The privacy filter

**For showing ObservANT in public without showing the home** (2026-10-14). With
`privacy = "pixelate"` in `observant.toml`, everything but the detected animals leaves the
camera as coarse blocks: 32 pixels at 640 wide, each its own mean colour. Only the boxes
stay sharp, each grown by 15 % on every side, since the model's boxes are up to half a
second old. With no box the whole picture is blocks, people included.
- It applies to everything that leaves the camera: the live stream, `/snapshot.jpg`, the
  arrival photos and the clips. The model still sees the whole picture, so detection works
  as before.
- Only the settings file sets it, then `sudo systemctl restart omni-observant`. No page can
  turn it off, so a visitor at a demo cannot either; nor can one unblur people by watching
  `person`, since the filter locks the classes to `observant.toml`'s. `/healthz` says `"privacy": "pixelate"`;
  the Stream page shows "Privacy filter on" under the camera's name, and the Camera page
  names it in its table.
- Arrival photos and clips recorded before it was turned on stay as they were. The other
  ObservANT cameras in `peers` show their own pictures, filtered only where they set it too.
- It costs little: one pass over each frame, no second model.

#### Tests

**`test-observant-package.sh` checks all three packages, and CI runs it.** `web.yml`'s
`observant` jobs run it on x64 and arm64 right after packaging. It runs as root in a
privileged `:latest`, prints one PASS or FAIL per check, and exits with the number of
failures.
A package without `debugutilsbad` reds five of its checks. Locally:

```bash
bash scripts/linux/observant/test-observant-package.sh   # root, inside :latest; finds out/'s packages
```

**What it checks**, for the .deb and the AppImage each installed in `:latest`
and run as the unit runs it, with a scrubbed environment as `omni-observant`:
- no shared object maps from outside the bundle, idle or with a viewer connected;
- the package's own files: the service user is in the `video` group, the settings file is
  `640 root:omni-observant` (an older world-readable one is made private), and the unit
  restarts whatever ended it and starts once the clock is set;
- `/healthz` says `ok` with no `problem` while frames come, and names the installed
  package's version;
- the Camera page's settings: `/settings` turns the picture and sets the score and the
  name, a restart keeps them, and it refuses a form post, a bad value and another site's
  page;
- "Not a cat" over the photo's boxes ends its visit, and the still photo watched again
  starts none;
- `apt remove` masks the unit and a reinstall unmasks and enables it; the AppImage's
  `--install` refuses a non-root caller, and its installed copy refuses `--install`;
- every setting the shipped `observant.toml` documents, uncommented, is one the service
  reads (`--print-config` takes them all);
- the installed unit loads without a warning (`systemd-analyze verify`) and keeps its
  sandbox: `systemd-analyze security` rates it 2.5 or less (1.8 on 2026-10-12, 8.7
  before the unit was sandboxed);
- headless Chrome played the stream over the LAN address;
- a tab put in the background, its connections then silenced by a proxy that keeps them open
  and carries nothing (`lib/silencing-proxy.py`, as a sleeping laptop leaves them), plays
  again after it shows (`lib/cdp-tab-return.mjs`, 2026-10-14);
- the bundled model found the cats in ANThology's `Summy&Thundy` photo (best score
  0.41 since 2026-10-13, 0.76 before: the portrait photo is bordered into the 4:3 frame
  now instead of stretched, so the cats are smaller), `/healthz` counted the visit and
  `/snapshot.jpg` served the frame as a JPEG;
- the arrival reached a stand-in webhook as a JSON POST, and `/arrival.jpg` served the
  frame it was seen on;
- the arrival's clip was encoded and named first in `/healthz`'s `clips`, `/arrival.mp4`
  served it as an MP4 and answered a byte range, `?t=` served that arrival's own and
  `404` for another, and the clip's event reached the stand-in webhook;
- the visit log timed the stay while the cat was in view, and a restart kept the visit,
  the arrival frame and the clip, and closed that visit at its last sighting;
- the web build left out the `wimp` and `webparagraph` renderers and the `*.symbols`
  debug maps, every file the server gzips came with its zopfli `.gz`, and the served
  `main.dart.wasm` was that `.gz` byte for byte;
- SIGTERM exits 0, and no inference fails on the way out;
- the AppImage's `--install`, a second `--install` over it, and `--uninstall --purge`
  left the expected files, and then none;
- the .deb installed over an edited `observant.toml` with no terminal, kept the edit, and
  `dpkg --purge` removed it;
- the flatpak, installed system-wide, answered `/healthz` from its sandbox, kept the
  cat's visits in its own state directory, and headless Chrome played its stream over
  the LAN address. Its first start wrote the sign-in
  entry, `--autostart off` removed it, and `flatpak uninstall` left nothing. A user
  install needs a D-Bus session that the container lacks, hence the system install.

On amd64 in `:latest` (2026-10-06), all 32 checks passed, and Chrome played 572 frames
from the sandboxed stream. The flatpak bundle is 63 MB. On arm64 on himbeere2
(2026-10-12) all 43 checks passed, with about 510 frames to Chrome each time, and all 47
once the arrival clip added four; all 51 on 2026-10-13, three of them on the
precompressed web build; all 69 on 2026-10-14, in 244 s (each line names its seconds; the
tab that comes back takes 113 of them, as it must stay hidden past the page's 60 s). CI passed the 41 from before the visit log on both
architectures (`web.yml` run 38197312619).

#### Where it ran

**On a Raspberry Pi 5 (himbeere2: imx219, Debian 13, kernel 6.18), 2026-10-05.**
The arm64 packages were built natively on the board in `:latest`, and CI's
`web.yml` builds them on `ubuntu-26.04-arm`. The .deb ran as the systemd unit:
- the camera came through `rpicam-vid`, with `rotate = 180` from the settings;
- exactly one `rpicam-vid` child ran, and no shared object mapped from outside
  the bundle;
- headless Chrome on another LAN host played 821 frames in 28 s;
- with `inference_fps = 2` the service used 132 % of one core, and the board ran
  at 63 °C;
- the same path, fed ANThology's photo, delivered the green YOLO boxes to that
  browser;
- after a reboot the unit was active about 11 s after the kernel started, on the Pi
  camera again, and the browser played about 30 fps.

Two notes from that board:
- **A firewall needs rules.** If ufw is active, `sudo ufw allow OmniObservANT` opens
  8080 and the WebRTC UDP range. himbeere2's existing rules already covered both.
- **A dark room is a black stream.** The imx219 has no IR, and the sensor itself
  read a mean Y of 0.5 out of 255 at night.

**On a SpacemiT riscv64 board (mintberrycrunch: Ubuntu 26.04, 8 cores, 16 GB, Logitech C270),
2026-10-13.** `package-observant.sh` built the riscv64 `.deb` natively on the board in the riscv64
`:latest`, in 7 min 53 s (the producer's cargo build 6 min 10 s); a Raspberry Pi 5 cannot emulate
it, because its 16 KiB pages break QEMU on the image's libraries. The unit:
- found the webcam on its own (`v4l2src /dev/video9 (C270 HD WEBCAM)`) among the SoC's
  codec and ISP nodes;
- needed `sudo ufw allow OmniObservANT`, as the package says, before the LAN reached it;
- streamed to headless Chrome on himbeere2 at about 24 fps (767 frames in 35 s);
- used 15 % of one core and 282 MB with the room empty, the model running every 5 s.

**The AppImage on himbeere2, 2026-10-06:**
- run plainly as the login user, it mounted through FUSE, and Chrome on another host
  played 844 frames in 28 s;
- the switch a user might make, `.deb` → `apt remove` → AppImage `--install` →
  `--uninstall` → `.deb`, ended enabled and running at every step, on the Pi camera,
  with `rotate = 180` kept;
- `--install` wrote a unit byte-identical to the .deb's.

Making that switch work took two fixes:
- `observant-install` treats the removed .deb's mask as a first install.
- It clears that package's `deb-systemd-helper` record, setting
  `DPKG_MAINTSCRIPT_PACKAGE`, since the tool refuses to run outside dpkg otherwise.
  Without that, the returning .deb read the AppImage's `--uninstall` as the admin's
  disable and stayed off.

**On a real desktop (Ubuntu, GNOME, amd64), 2026-10-08.** CI's flatpak from web run
37664412593 installed as a **user** install. `flatpak install --user` fetched its runtime
from Flathub: freedesktop 24.08, which Flathub marks end-of-life, because that run's
`:latest` predates the 26.08 refs (hub CON82). Its first run seeded the per-user
`observant.toml`, wrote `~/.config/autostart/org.kataglyphis.omni-observant.desktop`,
loaded the chain ORT and the model from `/app/observant`, and answered `/healthz` (test
pattern, no camera on that host). The host's Chrome played 582 frames from the LAN address.

**Not verified yet:** the flatpak's start at a real sign-in, and a USB webcam on an amd64
or arm64 board (mintberrycrunch's C270 above is riscv64).

#### Updates from the releases

Since 2026-10-15 the `.deb` updates itself. `omni-observant-update.timer`, enabled at install
like the service, runs `/opt/omni-observant/libexec/omni-observant-update` as root every night
at 03:30, spread over 45 minutes. It follows GitHub's `releases/latest` redirect to the newest
`v<version>` tag, and only when that version is newer than the installed one (never a
downgrade) it downloads `omni-observant_<version>_<arch>.deb`, checks it against the release's
`SHA256SUMS` and installs it with `dpkg -i`; the package's `postinst` restarts the service. No
release yet, a latest release from before the `v` tags, or one without this architecture's
package (riscv64, which no CI lane builds) leaves the camera as it is. Turn it off with `sudo
systemctl disable --now omni-observant-update.timer`, which an upgrade respects; `sudo
systemctl start omni-observant-update.service` checks at once, and `journalctl -u
omni-observant-update` shows what it did. `scripts/linux/observant/test-observant-update.sh`
runs it against a local stand-in for GitHub with fake packages in `web.yml`'s package jobs:
an update, no downgrade, a failing checksum and a missing architecture.

**A user install updates itself the same way, without root** (2026-10-16). Its user timer runs
`~/.local/opt/omni-observant/libexec/omni-observant-update --user`, which compares the newest
release with the bundle's `share/omni-observant/version`, downloads the release's tarball
(`omni-observant-<version>-linux-<arch>.tar.gz`; no FUSE needed, unlike the AppImage), checks it
against `SHA256SUMS` and runs its `observant --install --user`. The download goes to
`~/.cache/omni-observant/update` and is removed after: `/tmp` can be RAM, and a Pi Zero 2 W has
512 MB. Without dpkg the versions compare with `sort -V`. `systemctl --user start
omni-observant-update.service` checks at once. `test-observant-update.sh` covers it too, as uid
1001 and once with no dpkg on the `PATH`; `test-observant-package.sh` installs the AppImage's
`--install --user` as a plain user, runs it, upgrades it and purges it.

### The Windows ObservANT

**At a glance** (AGENTS.md § 2, until 2026-10-15):

`scripts/windows/observant/` — the Windows ObservANT, built and tested in `:winamd64`
(2026-10-06).
- `Package-ObservANT.ps1` builds one install folder, the zip and the MSI around it
  (`observant.wxs` through the hub's `Invoke-MsiPackage`).
  - Its DLL closure comes from the hub's `Copy-PeImportClosure`, plus the VC++ runtime.
  - The ORT comes from `Copy-ChainOrtBeside`, and `New-OrtProvenPayload` proves it.
  - The MSI's logon autostart is an all-users Startup-folder shortcut.
  - Its firewall rule is LAN-only and bound to the exe. It needs WiX's firewall
    extension, which the hub's final stage installs.
  - `-Msix` packs the same folder as an MSIX (`AppxManifest.xml`): a startup task, the
    `omni-observant` alias, and port rules for private and domain networks. It is signed
    by `-MsixPfx`, or else by a per-build test certificate whose `.cer` lands beside
    it. An unsigned result fails the build, because the hub's signing step only warns.
- `Test-ObservANTMsix.ps1` reads the MSIX anywhere. With `-Install` it deploys and runs
  the package on a desktop host, which Server Core cannot do (`0x80073D19`).
- `Test-ObservANTWindows.ps1` installs the MSI and runs the exe with a scrubbed
  environment.
- On Windows the exe finds its plugins, ORT and model itself (OxidANT `install.rs`).
- **openh264 is a required plugin on Windows**, because the image builds no `vpx`.
- Detail: `docs/source/camera-streaming.md` § *The Windows ObservANT*.

`scripts/windows/observant/Package-ObservANT.ps1` is the Windows twin of the
package above. Like `package-observant.sh` it stamps the build into the exe as `OBSERVANT_VERSION`
(the version and the short commit), which `/healthz` and the Camera page show. Run it inside
`:winamd64` with the web lane's build:

```powershell
pwsh -File scripts\windows\observant\Package-ObservANT.ps1 -WebRoot <build\web>
# out\omni-observant-<version>-windows-x64.msi   (one click: double-click it)
# out\omni-observant-<version>-windows-x64.zip   (the same folder, portable)
# with -Msix also:
# out\omni-observant-<version>-windows-x64.msix           (signed; see "The MSIX" below)
# out\omni-observant-<version>-windows-x64-testcert.cer   (only without -MsixPfx)
```

**Windows arm64 (since 2026-10-16).** `-Arch arm64` cross-builds the producer for
`aarch64-pc-windows-msvc` inside the image's arm64 bundle (`:winarm64`), takes its DLLs from the
arm64 runtime and the VC++ runtime from Visual Studio's arm64 redist, never the x64 container's
`System32`, and names the files `…-windows-arm64.*`. An x64 host cannot run them, so `web.yml`'s
`observant-windows-arm64-test` installs the MSI on `windows-11-arm`: first the hub's arch gate
over the unzipped package (67 binaries, all arm64, every import resolved), then the same
`Test-ObservANTWindows.ps1`, which there also checks the real firewall rule. That host has no
GStreamer of its own, so the viewer checks say SKIP, and the x64 run plays one. Media Foundation
on a desktop loads Microsoft's own Store codecs (HEVC, VP9), which the module check counts as
Windows. ONNX Runtime's own imports are part of the DLL closure: its `msvcp140_1.dll` was missing
from the first arm64 package, and from the x64 one on a PC without the VC++ redist.

**One folder.** `C:\Program Files\OmniAccelerANT Cat Cam` holds:
- `kataglyphis_observant.exe`;
- the DLLs it and its plugins import (`Copy-PeImportClosure`), plus the VC++ runtime,
  which a clean Windows lacks;
- the GStreamer plugin subset in `lib\gstreamer-1.0`, with Media Foundation and kernel
  streaming for the camera, and `openh264` as the stream's codec, since the image builds
  no `vpx`;
- the plugin scanner;
- the chain ONNX Runtime, proved by the hub's G6 census before packaging;
- `models\deim_dfine_n_coco.onnx` (its license and notice in `share\omni-observant\`) and the web build.

The exe points GStreamer, ONNX Runtime and the model at that folder itself (OxidANT's
`install.rs`), so it needs no launcher and nothing on PATH.

**The MSI** installs per machine. It adds:
- a Start menu folder, with **Cat Cam** and **Cat Cam page**;
- an entry in the all-users Startup folder, so ObservANT starts minimized at every
  logon. That's a logon task, by owner decision on 2026-10-06. A boot-time service would
  run in Session 0, and nobody has yet shown that a service can open a webcam there.

Both entries are features: you can deselect them in the installer, or switch autostart
off later in Task Manager under *Startup apps*. Settings go in
`%ProgramData%\omni-accelerant\observant.toml`; the template ships in
`share\omni-observant`.

**The MSI opens Windows Firewall to the local subnet**, so Windows does not ask. The
rule is bound to the exe, not to ports, so a changed `http_port` or ICE range in
`observant.toml` stays covered. It carries `IgnoreFailure`: a Windows without the firewall
service, such as the image's process-isolated container, still installs. Packaging needs
WiX's firewall extension, which the hub's final stage installs (`WIX_FIREWALL_EXT_VERSION`).

**`Test-ObservANTWindows.ps1` checks the MSI** inside `:winamd64` as admin. In the image,
14 checks passed on 2026-10-06:
- the MSI's firewall rule: LAN-only, bound to the exe, installing where it cannot apply;
- the silent install, its files, the Startup entry and the shortcuts;
- the installed exe run with only System32 on PATH: `/healthz` and the page answer, and
  every loaded module comes from the install folder or Windows, idle and with a viewer;
- a `webrtcsrc` viewer decoding 60 frames;
- the bundled model on the bundled ORT finding the cat;
- a silent uninstall that leaves nothing.

The container has no firewall service, so the test prints `SKIP` for the rule itself. On
a host whose firewall runs, two more checks run: the rule exists after the install and is
gone after the uninstall. `web.yml`'s `observant-windows` job packages and tests the MSI
around each run's web build.

**On a real Windows 11 host** (the dev box, no camera, 2026-10-06), the MSI installed
and uninstalled cleanly through UAC:
- its firewall rule was an inbound allow for the exe, limited to `LocalSubnet`;
- started from the Startup shortcut, the exe served the page and a test pattern
  (`no camera found`), with all 128 modules from its folder or Windows;
- a browser on another device on the LAN played the stream through that rule.

**The MSIX** (`-Msix`) packs the same folder, which G6 has already proved, with
`AppxManifest.xml`. It installs per user, needs no admin, and adds three things:
- a `desktop:StartupTask` for the logon start, which *Startup apps* turns off;
- the `omni-observant` alias, the Linux packages' command name;
- two firewall rules, TCP 8080 and UDP 40000-40099, on private and domain networks.

  MSIX rules take ports and profiles but no remote scope. So unlike the MSI's rule they
  are not limited to the local subnet, and a changed `http_port` or ICE range is not
  covered.

An MSIX installs only when Windows trusts its signer:
- `-MsixPfx` signs with your certificate; its password goes in `MSIX_PFX_PASSWORD`, and
  `-MsixPublisher` must equal its subject.
- Without it, a certificate made for that build signs, and its `.cer` lands beside the
  package. Import it into `LocalMachine\TrustedPeople` (admin), then double-click the
  `.msix`.
- `Package-ObservANT.ps1` refuses an unsigned result. The hub's signing step only warns when
  it fails.

**`Test-ObservANTMsix.ps1` checks the MSIX.**
- **Everywhere, in CI too:** the signature against the publisher, the manifest's startup
  task, alias and firewall rules, and the payload. These are six checks.
- **With `-Install`, on a desktop host:** it installs for the current user, finds the
  rules in Windows Firewall, starts the alias, reads `/healthz`, checks that every module
  comes from the package or Windows, and removes the package again.

Server Core cannot deploy an MSIX (`0x80073D19`), so CI runs only the first half.
On the dev box (2026-10-06), with the test certificate trusted:
- all 12 checks passed;
- himbeere2 reached the page through the MSIX's rules;
- the certificate came out of the store afterwards.

**Not verified yet:** a camera on Windows, the start at a real sign-in (the MSI's Startup
entry and the MSIX's startup task), and arm64.

### Cat detection stream (Rust, native)

`third_party/OxidANT/crates/observant` (`kataglyphis_observant`) is the
maintained producer: V4L2 or libcamera capture → ONNX detector (cats = COCO class
15) → boxes burned into the RGBA frames → `webrtcsink`. It runs its own
signalling server (`run-signalling-server=true`, plain `ws://`, default port
8443), so no separate signalling process is needed.

```bash
cd third_party/OxidANT
cargo build --release -p kataglyphis_observant
# The image's chain ONNX Runtime - OxidANT's loader refuses any other (2026-09-23),
# so this runs in the :latest image, where the path is the loader's fallback too.
ORT_DYLIB_PATH=/usr/local/lib/onnxruntime-cpu/lib/libonnxruntime.so \
  target/release/kataglyphis_observant --v4l2 /dev/video0
```

Since OxidANT dd496dc this binary is the service the package above installs:
- **It also answers on `:8080`.** That port serves the web build from
  `--web-root`, plus `/webrtc-ws` and `/healthz`. `--http-port 0` turns it off.
- **Its signalling server listens on loopback only.** A `serve.sh` on the same
  host still reaches it. A `serve.sh --producer-host` on another host needs the
  producer started with `--signalling-host 0.0.0.0`; `run-producer-pi.sh`
  passes that.
- **The old camera flags keep working.** `--camera auto`, `--config` and
  `--print-config` are added beside them.

`--test` streams a `videotestsrc` pattern, `--image <file>` (or
`$KATAGLYPHIS_CAT_IMAGE`) loops a still image — there is no default picture any
more (OxidANT deaea88, 2026-09-15; ANThology's `Thundy.jpg` is only named in the
error hint); without one of these the producer takes `camera` from its settings, `"auto"`
by default: a Raspberry Pi camera if attached, else a USB webcam. The model
default still resolves relative to the crate, so any checkout works. `--score`, `--width/--height/--fps`,
`--all-classes` and `--name` tune the stream. `--cert/--key` enable WSS on the
built-in server, but the signaller's rustls rejects self-signed CA certificates
(`CaUsedAsEndEntity`), so terminate TLS in a proxy instead — `serve.sh` does.

`--libcamera` captures through `libcamerasrc` instead of `v4l2src`; use it for
the Raspberry Pi CSI camera, whose `rp1-cfe` V4L2 nodes carry raw Bayer that
`videoconvert` cannot process. Inference runs on a background thread, so the
WebRTC stream keeps camera rate while the boxes lag one inference behind
(seconds per frame on a Pi 5 CPU). `--no-inference` skips the model entirely —
no ORT, no detector, frames published unannotated — for camera/WebRTC bring-up
and for hosts too weak to run the model. `--rotate 90|180|270` turns the stream clockwise with
`videoflip` (180 for a camera mounted upside down), and so do the page's ⟲ and ⟳ while it
runs; inference sees the turned frame, so the boxes still line up.

Serve the web build with the `/webrtc-ws` proxy. `serve.sh` also sends COOP/COEP,
which only the optional Rust core needs, and only in Firefox and Safari; the
Stream page streams without them, so `--http` drops TLS and the certificate
warning with it:

```bash
# once — web/pkg/ is a generated frb artefact (gitignored), so regenerate it
# the way the web CI lane does before building the frontend
rustup toolchain install nightly --component rust-src --target wasm32-unknown-unknown
cargo install --locked --version 2.13.0 flutter_rust_bridge_codegen  # the pin in third_party/OxidANT/Cargo.toml
flutter_rust_bridge_codegen build-web --release --rust-root third_party/OxidANT
flutter build web --release --wasm --no-web-resources-cdn

scripts/linux/observant/serve.sh          # :8444 TLS, proxies to :8443
scripts/linux/observant/serve.sh --http   # :8444 plain HTTP, no certificate
```

`serve.sh` also takes `--producer-host`/`--producer-port` to front a producer
on another board, and `--state-dir` so several instances (one per producer)
can run side by side. **The boards run the ObservANT package** (the current list:
[*Where it runs*](#where-it-runs)): producer, web build and page together on `http://<board>:8080/`. The
producer on `:8443` with `serve.sh` + the web build on `:8444` is the manual shape, for a
board without the package or an ad-hoc look at another board via `--producer-host`.

The boards the container shape was brought up on, before the package (today's cameras:
[*Where it runs*](#where-it-runs)):

| Board | Arch | Camera | Producer | Board-side quirks |
| --- | --- | --- | --- | --- |
| Raspberry Pi 5 | arm64 | imx219 (CSI) | Rust, inference | host-libcamera swap (rp1/pisp entity rename + libpisp 1.7) |
| Raspberry Pi Zero 2 W | arm64 | imx708 (CSI, mounted upside down) | `gst-launch`, no AI (512 MB) | host swap (vc4), `videoflip method=rotate-180` |
| Raspberry Pi 4 | arm64 | imx708 (CSI, mounted upside down) | Rust, inference | host swap (vc4), `/dev/dma_heap` ACLs, GCC 16 libs for ORT, `--rotate 180` |
| SpacemiT X100 | riscv64 | Logitech C270 (USB) | Rust, inference | no libcamera; camera ACL + udev rule, UFW `8443/8444` + UDP |

All four run the same `:latest` (a multi-arch index) and the same web
build; the board-side pieces are the producer, `serve.sh` and nginx.

**Starting is one command, and autostart is opt-in.** Each board carries a
small local `~/cat-cam.sh start|stop|status` that brings up (or tears down) its
producer and its nginx together and prints the board's own URL; after a reboot
that script is the whole procedure. A board that should come up on boot opts in
with a systemd unit whose `ExecStart` is that script — the Zero runs
`cat-cam.service` (`Type=oneshot`, `RemainAfterExit=yes`, `User=<user>`,
`ExecStop=~/cat-cam.sh stop`), the others deliberately have none. `start`
removes a stale container first: one left in `Created` state after a crash
blocks the named run with `name-store error` and would fail the boot start.

`signalingServerUrl` in `assets/settings/webrtc_settings.json` is
host-relative by default (`/webrtc-ws`); the web client resolves it against the
page's origin, so the same build works on localhost, a LAN IP and a Raspberry
Pi. Open `https://<host>:8444/` and accept the certificate warning, or run
`serve.sh --http` and open `http://<host>:8444/`, which has none.

USB cameras work with `--v4l2 /dev/videoX`. For a Pi's CSI camera use
`--libcamera`; on a Raspberry Pi 5 running the `:latest` image the
container route is:

```bash
# The producer runner lives in OxidANT, which owns crates/observant.
third_party/OxidANT/scripts/linux/observant/run-producer-pi.sh --build
scripts/linux/observant/serve.sh   # :8444 TLS, proxies to :8443
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
by source mtime, so after switching contexts `touch crates/observant/src/main.rs`
forces the recompile.
`third_party/OxidANT/scripts/linux/observant/run-producer-pi.sh` collects the
host's Raspberry Pi OS libcamera stack (0.7.2+rpt, which matches the kernel)
plus its library closure into OxidANT's own
`third_party/OxidANT/build/observant/hostlibs`, mounts that ahead of
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
by OxidANT's `third_party/OxidANT/scripts/linux/observant/run-producer-pi.sh`
(or refresh it there with `--libs-only`) to the Zero, then:

```bash
# On the Zero. ~/cat-cam/hostlibs is the dev host's
# third_party/OxidANT/build/observant/hostlibs, and IMAGE is the family CI
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
overrides the `LD_LIBRARY_PATH` above — hence `--entrypoint bash` (`:latest`
since 2026-09-29 appends its libcamera *after* a caller's path instead, hub CON23,
so the bypass should no longer be needed; it stays here until a board has run
the recipe without it); and
`webrtcsink`'s `meta` must be a space-free structure in gst-launch
(`meta="meta,name=Zero-Cat-Cam"`; a space fails to parse). For its own
homepage, install nginx on the board (`sudo apt install nginx`; it lands in
`/usr/sbin`, which is not on the user's `PATH`), open UFW (`8444/tcp` plus the
WebRTC UDP range), copy the web build and `serve.sh` over, and run it there:

```bash
# from the dev host (<board> is the target's ssh name)
rsync -a build/web/ <board>:cat-cam/build/web/
rsync -a scripts/linux/observant/serve.sh \
  <board>:cat-cam/scripts/linux/observant/serve.sh
# on the Zero (serve.sh derives its repo root from its own path, so the
# scripts/linux/observant/ layout under ~/cat-cam is deliberate)
cd ~/cat-cam && PATH=/usr/sbin:$PATH bash scripts/linux/observant/serve.sh
```

Media is WebRTC UDP, browser ↔ Zero, direct on the LAN. If the container is
too heavy for the board, `scripts/linux/observant/package-producer-bundle.sh`
exports a container-less aarch64 bundle (producer + pruned GStreamer + the
image's glibc, ~180 MB) that runs against the host's libcamera with no
container and no toolchain; and `--no-inference` is the next step up from this
`gst-launch` bring-up. Its ONNX Runtime is the image's chain copy
(`ORT_LIB_LOCATION`), and the assembling image run ends with ANTfrastructure's
G6 census over the finished bundle: every ORT binary byte-identical to that
image's chain ORT, and the producer — given an `$ORIGIN/../lib` RUNPATH, the
same directory `run.sh` passes to the bundled loader — resolving to it.

**Other VC4/unicam Pis (e.g. Pi 4).** The same host-libcamera swap applies,
but the Rust producer fits there, and it needs **no board-specific runner**:
the Pi 5's runner works as-is — it collects the host libcamera closure, ACLs
`/dev/{video,media,dma_heap}*` (the dma_heap nodes matter here, or libcamera
reports `Could not open any dma-buf provider` and registration fails with
`-12`/ENOMEM) and takes the image's loader paths from its own `media-env.sh`,
which put the source-built GCC's `lib64` (`/opt/gcc-16.2.0/lib64` today) on
`LD_LIBRARY_PATH` — what the image's ONNX Runtime needs (`GLIBCXX_3.4.36 not
found` otherwise).
The Pi 4's camera here is mounted upside down, so:

```bash
third_party/OxidANT/scripts/linux/observant/run-producer-pi.sh --build --rotate 180
```

Its homepage works like the Zero's: nginx is preinstalled on Pi OS, `serve.sh`
runs with `PATH=/usr/sbin:$PATH` from a repo checkout (`~/OmniAccelerANT` here;
its board-local producer wrapper is `~/zweckle-producer.sh`).

**RISC-V SoC (SpacemiT X100).** `:latest` is a multi-arch index
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
  'cd /workspace && cargo build --release --locked -p kataglyphis_observant'

# run (detached; the board's wrapper is ~/x100-producer.sh)
nerdctl run -d --rm --name x100-producer --user 0:0 --privileged --network host \
  -v /dev:/dev -v "$HOME/OxidANT":/workspace \
  -v kataglyphis-cat-target:/cargo-target \
  -e ORT_DYLIB_PATH=/usr/local/lib/onnxruntime-cpu/lib/libonnxruntime.so -e RUST_LOG=info \
  --entrypoint /cargo-target/release/kataglyphis_observant "$IMAGE" \
  --v4l2 /dev/video9 --listen-port 8443 --name "Cat Cam"
```

If you front it from another host instead (`serve.sh --producer-host`), add
`--signalling-host 0.0.0.0` to the producer, and give `serve.sh` its
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

### Raspberry Pi (libcamera, example)

```bash
GST_DEBUG=3 gst-launch-1.0 \
  libcamerasrc ! video/x-raw,format=RGB,width=640,height=360,framerate=30/1 ! \
  videoconvert ! video/x-raw,format=I420 ! queue ! \
  vp8enc deadline=1 threads=2 ! queue ! \
  webrtcsink signaller::uri="ws://127.0.0.1:8444" name=ws meta="meta,name=gst-stream"
```

## 4) Run the web frontend

```bash
flutter run -d web-server --profile --web-port 8080 --web-hostname 0.0.0.0
```

## No secure context needed

Moved here from AGENTS.md on 2026-10-15, which keeps the rule and links this detail.

**The Stream page needs no secure context; only the Rust wasm core wants
isolation, and the web boots without it.** The page is receive-only
gstwebrtc-api JS. `pkg/oxidant_bg.wasm` is a threads build whose shared
memory Firefox and Safari refuse unless the page is cross-origin isolated
(COOP/COEP, honoured only on HTTPS or localhost); Chromium creates it anyway.
On web `main()` therefore treats a failed `RustLib.init()` as optional
(`lib/src/boot/rust_core.dart`): the app starts, and only the About page's
Rust demo goes dark. No code ever checked `crossOriginIsolated`, whatever
older notes said. Measured 2026-10-05 on the web lane's build with
`:latest`'s Chrome for Testing 154, over plain HTTP from a non-loopback
address: the app boots with the core, and boots without it when
`oxidant_bg.wasm` is blocked — the path Firefox and Safari take, neither of
which was run. `serve.sh --http` serves that plain-HTTP page, no certificate
warning. Without `--http` it terminates TLS on 8444, because the GStreamer
signalling server cannot end TLS for this repo's certificates (rustls
rejects a self-signed one with `CaUsedAsEndEntity`); the producer's
`--cert/--key` exist, the proxy is the supported path. Either way it proxies
`/webrtc-ws` to the producer's plain `ws://` server (port 8443).

## Troubleshooting

- **An ObservANT camera reports cats that are not there.** Open its page, *Camera* in the bottom
  bar. While the false box shows in the preview, press "Not a cat": ObservANT ignores
  that spot for good. A false arrival from earlier is under "Recent detections", with the
  same button. Since 2026-10-14 only a detection where something moved starts a visit,
  so a still object rarely does. For a false cat that moves, the line under the detection
  slider names the last detection's score: move the slider above it. Too high and a cat
  in poor light is missed too: a real cat at the feeding trough scored 0.72, the drying
  rack 0.26 to 0.65.
- **The picture is sideways after the board was moved.** ⟲ and ⟳ on the same page turn
  it a quarter at a time; detection, the arrival picture and the clips turn with it.
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
  one, delete `build/observant/tls/` and let it rebuild.
- On a host firewall (e.g. UFW on Raspberry Pi OS), allow `8444/tcp` and the
  WebRTC media UDP range (`32768:60999/udp`, LAN-scoped is enough) — the
  browser otherwise connects for signalling but ICE never completes.
- Each `serve.sh` instance (one per board) listens on its own port, and the
  **dev host's** firewall has to allow every one of them, not just the first:
  a second board's page stays unreachable while the first board's still works,
  which reads like a producer problem but is a missing `ufw allow 8446/tcp`.