# Camera Streaming

Practical WebRTC streaming and inference pipelines for Kataglyphis.

- [Rust-owned webcam inference (local, no WebRTC)](#rust-owned-webcam-inference-local-no-webrtc)
  - [Checking the knt ABI](#checking-the-knt-abi)
  - [Relocatable Linux bundles](#relocatable-linux-bundles)
- [WebRTC pipelines (Linux / web)](#webrtc-pipelines-linux--web)
  - [The cat cam package](#the-cat-cam-package)
    - [Installing it](#installing-it)
    - [Cameras](#cameras)
    - [Detection, visits and /healthz](#detection-visits-and-healthz)
    - [Arrival picture, video and webhook](#arrival-picture-video-and-webhook)
    - [Home Assistant](#home-assistant)
    - [The Stream page](#the-stream-page)
    - [Tests](#tests)
    - [Where it ran](#where-it-ran)
  - [The Windows cat cam](#the-windows-cat-cam)
  - [Cat detection stream (Rust, native)](#cat-detection-stream-rust-native)
- [1) Start the signalling server](#1-start-the-signalling-server)
- [2) Export plugin path (if required)](#2-export-plugin-path-if-required)
- [3) Start a stream source](#3-start-a-stream-source)
  - [USB webcam](#usb-webcam)
  - [Pylon camera](#pylon-camera)
  - [Raspberry Pi / Orange Pi (example)](#raspberry-pi--orange-pi-example)
- [4) Run the web frontend](#4-run-the-web-frontend)
- [Troubleshooting](#troubleshooting)

## Rust-owned webcam inference (local, no WebRTC)

On Windows the **Stream** page runs a fully local webcam → ONNX → texture pipeline
owned end-to-end by Rust — no signalling server, no browser. Video frames never
cross the Dart bridge; only detection metadata does.

> **Linux has the same design as of 2026-09-16; a frame has crossed it since 2026-10-05.**
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
> **A test-pattern frame reaches the texture on every native lane run.**
> `integration_test/webcam_frame_test.dart` starts `RustWebcamView` on
> `videotestsrc` under Xvfb and polls the plugin's `hasPushedFrame`, the flag
> `knt_push_frame` sets. A camera changes only the source, so the push path
> needs none. A green lane is still not a working *camera*: real V4L2 capture
> on Linux remains a manual check.

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
bundle and drives the integration test under the image's `xvfb-run` — but no
camera, so nothing there pushes a frame. Seeing one needs a camera — on the
Windows dev box that means the `usbipd attach --wsl` route in AGENTS.md § 4.

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
  ORT in that case. Plus the 59 MB detector model at
  `data/resources/models/yolov10m.onnx` — the standard model, bundled by default
  (owner decision 2026-10-01); `KATAGLYPHIS_BUNDLE_MODEL=0` drops it for an
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

### The cat cam package

`scripts/linux/cat-stream/package-catcam.sh` turns the producer below into one
installable service. Run it inside `:latest`, with the web lane's `build/web` as
its web root:

```bash
bash scripts/linux/cat-stream/package-catcam.sh --web-root build/web
# out/omni-accelerant-catcam_<version>_<deb-arch>.deb            Debian, Ubuntu, Raspberry Pi OS
# out/omni-accelerant-catcam-<version>-<uname-arch>.AppImage     any glibc distro
# out/omni-accelerant-catcam-<version>-<uname-arch>.flatpak      any flatpak desktop; USB cameras, sign-in start
# out/omni-accelerant-catcam-<version>-linux-<deb-arch>.tar.gz   the same bundle, unpacked
```

The flatpak's `flatpak-builder` runs in bubblewrap, so the script needs a privileged
container (`nerdctl run --privileged`).

Install it with `sudo apt install ./omni-accelerant-catcam_<version>_<arch>.deb`,
or anywhere else with `sudo ./omni-accelerant-catcam-<version>-<arch>.AppImage --install`.
Then open `http://<host>:8080/` from any browser on the network.

Everything it serves is on that one port, plain HTTP:

| Path | Answers |
| --- | --- |
| `/` | the web app; its Stream page plays the camera and shows the cat's status, visits and last arrival |
| `/healthz` | JSON: the live camera, `model_runs`, `rotate`, and the cat's `in_view`, `last_seen`, `visits`, `last_score`, `recent` visits, the newest `clip`'s arrival and every kept one's (`clips`) |
| `/snapshot.jpg` | the latest frame, boxes drawn |
| `/arrival.jpg` | the frame the last arrival was confirmed on; `404` until a cat has come |
| `/arrival.mp4` | the last arrival as an H.264 clip, 3 s before it to 7 s after; `?t=<arrival time>` that arrival's own, of the last five; byte ranges answered; `404` until one is encoded, or once that arrival's is dropped |
| `/rotate` | `POST {"rotate": 90}` (`application/json` only) turns the picture: 0, 90, 180 or 270 degrees clockwise |
| `/webrtc-ws` | the WebRTC signalling, forwarded to the producer's own server on loopback `:8443` |

**The picture turns from the page.** Under the video, ⟲ and ⟳ turn it a quarter each way
(2026-10-13), for a board that is easily moved. The cat cam turns the picture itself, before
the model sees it, so detection, `/arrival.jpg` and the clips turn with the stream, and the
running capture follows on its next frame, with no restart and no reconnect. The angle is
kept in the state directory (`settings.json`) and wins over `rotate` in `catcam.toml`, which
the service cannot write. At 90 and 270 the upright picture is bordered into the frame,
black at its sides, instead of stretched: until then a quarter turn squeezed a 4:3 picture
into 4:3 the other way round, and a cupboard looked square. `/rotate` takes JSON only, so
another site's page cannot turn the camera with a plain form post.

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

**The AppImage either runs or installs.** Started plainly, it runs the cat cam in the
foreground as the calling user, which needs the `video` group. `--install` copies it
to `/opt/omni-accelerant-catcam` and sets up the same service as the .deb:
- the unit goes to `/etc/systemd/system`, and `omni-catcam` to `/usr/local/bin`;
- `--no-autostart` leaves the service disabled;
- running it again with a newer AppImage upgrades, keeping the settings and the
  enabled or disabled state;
- `omni-catcam --uninstall [--purge]` removes it.

The installer is `libexec/catcam-install` in the bundle, so the tarball's
`sudo ./catcam --install` does the same. It refuses while the .deb is installed,
and the .deb's `postinst` uses it to create the user. Without FUSE, set
`APPIMAGE_EXTRACT_AND_RUN=1`.

**The flatpak starts at sign-in, not at boot, and takes USB cameras only.** Install it
with `flatpak install ./omni-accelerant-catcam-<version>-<arch>.flatpak`; a desktop
without the freedesktop runtime it names fetches that from Flathub. Start it with
`flatpak run org.kataglyphis.omni-accelerant-catcam`.
- It runs the same bundle, from `/app/catcam`, in a sandbox that has the network, every
  device (`--device=all`, as the app's flatpak has) and the host's `~/.config/autostart`.
- Its first run seeds `~/.var/app/org.kataglyphis.omni-accelerant-catcam/config/omni-accelerant/catcam.toml`
  from the template and writes the sign-in entry. `flatpak run --command=omni-catcam
  org.kataglyphis.omni-accelerant-catcam --autostart off|on` switches it.
- A flatpak cannot carry a systemd unit, so it starts when the user who ran it once
  signs in, never at boot.
- It cannot use a Raspberry Pi camera. `rpicam-vid` is a host tool the sandbox cannot see,
  and the image's libcamera cannot drive a Pi 5. On a Pi, use the .deb or the AppImage.

**What the bundle carries.** Everything lives in `/opt/omni-accelerant-catcam`:
- the producer;
- the GStreamer plugins it uses (`rswebrtc` and its WebRTC/DTLS/SRTP stack
  included), and NSS's crypto modules beside `libnss3`;
- the image's chain ONNX Runtime, proved by the hub's G6 census before packaging;
- `yolo26n.onnx` (AGPL-3.0, see `share/doc/…/NOTICE-model`);
- the web build;
- the image's own loader, glibc and GCC 16 `libstdc++`. The chain ORT needs
  `GLIBC_2.43` and `GLIBCXX_3.4.36`, which no current distro ships.

The `catcam` launcher runs the producer through that loader with
`--library-path`, never `LD_LIBRARY_PATH`. A child it starts, such as the host's
`rpicam-vid`, therefore keeps the host's libraries. libcamera is the one library
left to the host, because its IPA and tuning files must match the host kernel.

**What the .deb does on install.**
- It creates the `omni-catcam` system user and adds it to `video` and `render`.
- It enables and starts `omni-catcam.service`, so the cat cam comes back after a
  reboot.
  - `systemctl disable --now omni-catcam` turns that off, and upgrades keep the
    choice.
  - `OMNI_CATCAM_AUTOSTART=0` on the first install leaves the service disabled.
- `/etc/omni-accelerant/catcam.toml` is written at the first install, with every
  setting commented out, and never overwritten. `omni-catcam --print-config`
  shows the settings in effect.
  - It is deliberately not a conffile. dpkg asks about an edited conffile on every
    upgrade that changes it, and over SSH or in an unattended upgrade nobody
    answers, so the install hangs. Found on himbeere2, 2026-10-05.
  - `apt purge` removes it.
- `sudo ufw allow OmniCatCam` opens `8080/tcp` and the WebRTC range
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
`/snapshot.jpg` is the latest frame, boxes included, for a quick look without
WebRTC: `curl -o cat.jpg http://<host>:8080/snapshot.jpg`. A cat counts after two
detections in a row and leaves after about 3 s without one, so a lone hit near the
score threshold draws no box and logs nothing. While nothing moves and no cat is in
sight the model runs only every 5 s (`idle_inference_fps`), and not at all while the
picture is black; motion or a cat brings back `inference_fps`, and `/healthz` counts the
runs (`model_runs`). On a Pi 5 that took a still, empty scene from 74 % to 12 % of a
core, and a dark room at night to 2 %. `inference = "auto"` turns the model
off below 1 GiB of RAM.

A live `/healthz` from himbeere2 at night (2026-10-12), the camera's name shortened:

```json
{
  "camera": "Raspberry Pi camera via rpicam-vid (imx219 [3280x2464 10-bit RGGB] (…))",
  "cat": { "in_view": false, "last_score": null, "last_seen": null, "recent": [], "visits": 0 },
  "inference": true,
  "model_runs": 4,
  "name": "Trouble Tabbls Cat Cam",
  "ok": true
}
```

`model_runs` counts since the service started. `visits`, `last_seen`, `last_score` and
`recent` survive a restart, and so does `/arrival.jpg`: the service keeps them in
`/var/lib/omni-accelerant-catcam`, its systemd state directory, on every arrival and
departure and once more when it stops. A visit the stop cut short is closed at the cat's
last sighting when the service starts again; after a power cut, which writes nothing, at
the last arrival or departure written. The flatpak keeps them in its own `~/.var/app/…/.local/state`, the Windows
cat cam in `%LOCALAPPDATA%\omni-accelerant-catcam`. `last_seen` and `last_score` stay `null` until a cat has been in view.

The Stream page reads the same `/healthz` every 5 s (`CatStatusLine` in
`lib/Pages/StreamPage/cat_status.dart`): under the video it puts the cat cam's `name`,
then "Cat in view", "Cat last seen: 14:32" or "No cat seen yet", in English or German,
the three latest visits ("Recent visits: 14:32 (3 min) · 11:05 (10 min)"; one still going
on has no stay yet), and from the first visit on the last arrival's picture. Its URL carries the visit count
(`/arrival.jpg?visit=3`), not `last_seen`, which moves on every model run while a cat
stays, so the page fetches the picture once per visit. On the photo, with the cat in
view for 35 s, headless Chrome sent seven `/healthz` requests and one `/arrival.jpg`
(2026-10-12). Served from anywhere else, where `/healthz` is no cat cam's answer, it
shows only the title.

#### Arrival picture, video and webhook

**It can tell you the cat came.** Set `notify_url` in `catcam.toml` and the service
POSTs a JSON event there whenever a cat arrives or leaves:

```json
{"event": "arrived", "name": "Trouble Tabbls Cat Cam", "time": 1791763273,
 "detections": 2, "best_score": 0.76, "snapshot": "/arrival.jpg"}
{"event": "clip", "name": "Trouble Tabbls Cat Cam", "time": 1791763273,
 "best_score": 0.76, "clip": "/arrival.mp4", "snapshot": "/arrival.jpg"}
{"event": "left", "name": "Trouble Tabbls Cat Cam", "time": 1791763315, "stayed_s": 42,
 "arrived": 1791763273, "best_score": 0.76}
```

`/arrival.jpg` is the frame the arrival was confirmed on, boxes included, so a
notification can show what triggered it. A Home Assistant webhook trigger takes the events
as they are: its URL `http://<home-assistant>:8123/api/webhook/<id>` is the
`notify_url`, and `trigger.json.event` tells arrival from departure. https works too.
Deliveries run on a thread of their own with a 5 s timeout, a failed one is logged and
dropped, and the log names only the URL's scheme and host, because a webhook's path is
often its secret.

**Each arrival is a 10 s video too.** The capture thread hands every annotated frame to
`clip.rs`, which keeps one in three (10 fps of the 30) for the last 3 s, as buffer
references, so nothing is copied. An arrival takes those and the next 7 s and gives them to
a thread of its own, which encodes them with `openh264enc` at 800 kbit/s (about 1 MB a
clip at 640x480), `h264parse` and `mp4mux faststart=true`, so the index comes first and a
browser starts playing at once. `/arrival.mp4` serves it with byte ranges, which Safari's
`<video>` needs; `/healthz` names the newest one's arrival as `cat.clip`; and `notify_url`
gets a `clip` event once it is written, with the arrival's `time` and `best_score`.
**The last five clips stay addressable by arrival**, as `clip-<time>.mp4` in the state
directory, across a restart too: `/arrival.mp4?t=<time>` serves that arrival's own, and
`404` once it is dropped, never a newer one. A false visit right after the cat (33 of them
on himbeere2's morning of 2026-10-12) would otherwise have put its clip behind the cat's
notification. The arrival event carries the visit log's own time, the one the clip is kept
under. The Stream page links the newest clip by its time once `cat.clip` is the newest
visit, so it never offers the previous cat's clip, and lists the other kept ones beside it
("Earlier videos: ▶ 18:07 ▶ 18:05", from `cat.clips`).
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
one of the three records no clip and says which at start. `test-catcam-package.sh`
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
  himbeere2's frame made 33 "visits" between 0.26 and 0.44, and a cat in the bundled photo
  scores 0.76. The condition keeps those off the phone while the visit log still counts
  them; raising `score` instead would drop them from both. It is not enough on its own:
  at 21:57 the same object scored 0.65 and reached the phone (BACKLOG, *False arrivals*).
- **The companion app's `minimal` build has no push service.** It receives notifications
  only over its own connection to Home Assistant, so set *Persistent connection* to
  *Always* in its server settings. The `full` build gets them through Firebase. A push
  while the app is not connected fails with `not connected to local push notifications`
  and is gone; himbeere2's automations therefore send each notification three times a
  minute apart under one `tag` with `alert_once: true`, and `continue_on_error` on the call,
  so a repeat replaces a delivered one silently and reaches a phone that reconnected.
- **The picture loads from the phone,** so `catcam_base_url` must be an address the phone
  can reach: an IP or a name its network resolves, not loopback.

A test arrival posted to that webhook reached the owner's phone on 2026-10-12.

**The same notification learns when the cat left.** A departure names the arrival it
ends (`arrived`) and that arrival's `best_score`, so the automation above takes it under
the same 0.45 and updates the notification by its `tag`: "Katze war da … War 4 Min. da."
A clip event carries `stayed_s` too when the visit was over before its clip was encoded.
himbeere2's automation keeps the last departure in an `input_text`
(`"<arrival time> <seconds>"`), so its minute-apart tries of an arrival keep the stay a
departure in between added.

**At 21:00 a summary.** Each notified arrival appends its time to another `input_text`,
which the midnight reset clears with the day's counter, and a time trigger sends
"Heute 2 Katzenbesuche: 07:12, 18:30." or "Heute keine Katze gesehen." under a tag of its
own.

**More than one cat cam.** Each posts to a webhook of its own, and one automation takes
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
polls `http://127.0.0.1:8080/healthz` every 30 s when it runs on the cat cam's host:
`cat.in_view`, `cat.last_seen`, `cat.visits`, `cat.recent[0].stayed_s` and `ok` become
sensors, and with the cat cam unreachable they all turn `unavailable`. On himbeere2
(2026-10-12):
- the arrival automation increments two counters, *today* and *total*, so they count only
  what reached the phone; a template sensor with `state_class: total_increasing` mirrors
  *total*, which lets a `statistics-graph` card draw visits per day, and a time trigger
  resets *today* at midnight;
- `binary_sensor.cat_cam_online` unavailable or off for five minutes sends "Cat cam
  offline", and its return after such an outage sends "Cat cam wieder da"; a Home
  Assistant restart's few seconds stay quiet. Stopping `omni-catcam` for 5 min 45 s sent
  the first at 5 min, on the dot.
- **A sensor that has no value yet needs `availability`, not `none`.** A `rest` template
  that returns `none` renders the text "None", which a timestamp sensor logs as an invalid
  timestamp on every poll and a duration sensor refuses at load (`ValueError: ... has the
  non-numeric value: 'None'`). A new camera has no sighting yet, and a visit in progress
  has a null `stayed_s`, so `last_seen` and the stay are guarded with `availability`
  templates (`{{ value_json.cat.last_seen is number }}`) and show unavailable instead.

#### The Stream page

**An open page survives a restart of the service.** The page sees its producer go and
come back and consumes the new one, with no reload: on himbeere2 (2026-10-12) headless
Chrome's video was playing at 30 fps again about 10 s after `systemctl restart
omni-catcam`, as an upgrade does it.

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

**One port reaches it.** The page and the `/webrtc-ws` signalling share `:8080`:
the service forwards the WebSocket upgrade to its own signalling server on
loopback `:8443`. Media goes over host candidates only unless `stun_server` is
set, so the stream stays on the LAN. No TLS, no `serve.sh`, no container.

#### Tests

**`test-catcam-package.sh` checks all three packages, and CI runs it.** `web.yml`'s
`catcam` jobs run it on x64 and arm64 right after packaging. It runs as root in a
privileged `:latest`, prints one PASS or FAIL per check, and exits with the number of
failures.
A package without `debugutilsbad` reds five of its checks. Locally:

```bash
bash scripts/linux/cat-stream/test-catcam-package.sh   # root, inside :latest; finds out/'s packages
```

**What it checks**, for the .deb and the AppImage each installed in `:latest`
and run as the unit runs it, with a scrubbed environment as `omni-catcam`:
- no shared object maps from outside the bundle, idle or with a viewer connected;
- every setting the shipped `catcam.toml` documents, uncommented, is one the service
  reads (`--print-config` takes them all);
- the installed unit loads without a warning (`systemd-analyze verify`) and keeps its
  sandbox: `systemd-analyze security` rates it 2.5 or less (1.8 on 2026-10-12, 8.7
  before the unit was sandboxed);
- headless Chrome played the stream over the LAN address;
- the bundled model found the cats in ANThology's `Summy&Thundy` photo (best score
  0.76; 0.72 before the frames stayed I420), `/healthz` counted the visit and
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
- the .deb installed over an edited `catcam.toml` with no terminal, kept the edit, and
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
precompressed web build. CI passed the 41 from before the visit log on both
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
- **A firewall needs rules.** If ufw is active, `sudo ufw allow OmniCatCam` opens
  8080 and the WebRTC UDP range. himbeere2's existing rules already covered both.
- **A dark room is a black stream.** The imx219 has no IR, and the sensor itself
  read a mean Y of 0.5 out of 255 at night.

**The AppImage on that board, 2026-10-06:**
- run plainly as the login user, it mounted through FUSE, and Chrome on another host
  played 844 frames in 28 s;
- the switch a user might make, `.deb` → `apt remove` → AppImage `--install` →
  `--uninstall` → `.deb`, ended enabled and running at every step, on the Pi camera,
  with `rotate = 180` kept;
- `--install` wrote a unit byte-identical to the .deb's.

Making that switch work took two fixes:
- `catcam-install` treats the removed .deb's mask as a first install.
- It clears that package's `deb-systemd-helper` record, setting
  `DPKG_MAINTSCRIPT_PACKAGE`, since the tool refuses to run outside dpkg otherwise.
  Without that, the returning .deb read the AppImage's `--uninstall` as the admin's
  disable and stayed off.

**On a real desktop (Ubuntu, GNOME, amd64), 2026-10-08.** CI's flatpak from web run
37664412593 installed as a **user** install. `flatpak install --user` fetched its runtime
from Flathub: freedesktop 24.08, which Flathub marks end-of-life, because that run's
`:latest` predates the 26.08 refs (hub CON82). Its first run seeded the per-user
`catcam.toml`, wrote `~/.config/autostart/org.kataglyphis.omni-accelerant-catcam.desktop`,
loaded the chain ORT and the model from `/app/catcam`, and answered `/healthz` (test
pattern, no camera on that host). The host's Chrome played 582 frames from the LAN address.

**Not verified yet:** a USB webcam, and the flatpak's start at a real sign-in.

### The Windows cat cam

`scripts/windows/cat-stream/Package-CatCam.ps1` is the Windows twin of the
package above. Run it inside `:winamd64` with the web lane's build:

```powershell
pwsh -File scripts\windows\cat-stream\Package-CatCam.ps1 -WebRoot <build\web>
# out\omni-accelerant-catcam-<version>-windows-x64.msi   (one click: double-click it)
# out\omni-accelerant-catcam-<version>-windows-x64.zip   (the same folder, portable)
# with -Msix also:
# out\omni-accelerant-catcam-<version>-windows-x64.msix           (signed; see "The MSIX" below)
# out\omni-accelerant-catcam-<version>-windows-x64-testcert.cer   (only without -MsixPfx)
```

**One folder.** `C:\Program Files\OmniAccelerANT Cat Cam` holds:
- `kataglyphis_cat_webrtc.exe`;
- the DLLs it and its plugins import (`Copy-PeImportClosure`), plus the VC++ runtime,
  which a clean Windows lacks;
- the GStreamer plugin subset in `lib\gstreamer-1.0`, with Media Foundation and kernel
  streaming for the camera, and `openh264` as the stream's codec, since the image builds
  no `vpx`;
- the plugin scanner;
- the chain ONNX Runtime, proved by the hub's G6 census before packaging;
- `models\yolo26n.onnx` and the web build.

The exe points GStreamer, ONNX Runtime and the model at that folder itself (OxidANT's
`install.rs`), so it needs no launcher and nothing on PATH.

**The MSI** installs per machine. It adds:
- a Start menu folder, with **Cat Cam** and **Cat Cam page**;
- an entry in the all-users Startup folder, so the cat cam starts minimized at every
  logon. That's a logon task, by owner decision on 2026-10-06. A boot-time service would
  run in Session 0, and nobody has yet shown that a service can open a webcam there.

Both entries are features: you can deselect them in the installer, or switch autostart
off later in Task Manager under *Startup apps*. Settings go in
`%ProgramData%\omni-accelerant\catcam.toml`; the template ships in
`share\omni-accelerant-catcam`.

**The MSI opens Windows Firewall to the local subnet**, so Windows does not ask. The
rule is bound to the exe, not to ports, so a changed `http_port` or ICE range in
`catcam.toml` stays covered. It carries `IgnoreFailure`: a Windows without the firewall
service, such as the image's process-isolated container, still installs. Packaging needs
WiX's firewall extension, which the hub's final stage installs (`WIX_FIREWALL_EXT_VERSION`).

**`Test-CatCamWindows.ps1` checks the MSI** inside `:winamd64` as admin. In the image,
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
gone after the uninstall. `web.yml`'s `catcam-windows` job packages and tests the MSI
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
- the `omni-catcam` alias, the Linux packages' command name;
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
- `Package-CatCam.ps1` refuses an unsigned result. The hub's signing step only warns when
  it fails.

**`Test-CatCamMsix.ps1` checks the MSIX.**
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

`third_party/OxidANT/crates/cat_webrtc` (`kataglyphis_cat_webrtc`) is the
maintained producer: V4L2 or libcamera capture → YOLO ONNX (cats = COCO class
15) → boxes burned into the RGBA frames → `webrtcsink`. It runs its own
signalling server (`run-signalling-server=true`, plain `ws://`, default port
8443), so no separate signalling process is needed.

```bash
cd third_party/OxidANT
cargo build --release -p kataglyphis_cat_webrtc
# The image's chain ONNX Runtime - OxidANT's loader refuses any other (2026-09-23),
# so this runs in the :latest image, where the path is the loader's fallback too.
ORT_DYLIB_PATH=/usr/local/lib/onnxruntime-cpu/lib/libonnxruntime.so \
  target/release/kataglyphis_cat_webrtc --v4l2 /dev/video0
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
error hint), and without one of these a live-source flag is required. The model
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
and for hosts too weak to run YOLO. `--rotate 90|180|270` flips the stream with
`videoflip` (180 for a camera mounted upside down); inference sees the rotated
frame, so the boxes still line up.

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

scripts/linux/cat-stream/serve.sh          # :8444 TLS, proxies to :8443
scripts/linux/cat-stream/serve.sh --http   # :8444 plain HTTP, no certificate
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
third_party/OxidANT/scripts/linux/cat-stream/run-producer-pi.sh --build --rotate 180
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
  'cd /workspace && cargo build --release --locked -p kataglyphis_cat_webrtc'

# run (detached; the board's wrapper is ~/x100-producer.sh)
nerdctl run -d --rm --name x100-producer --user 0:0 --privileged --network host \
  -v /dev:/dev -v "$HOME/OxidANT":/workspace \
  -v kataglyphis-cat-target:/cargo-target \
  -e ORT_DYLIB_PATH=/usr/local/lib/onnxruntime-cpu/lib/libonnxruntime.so -e RUST_LOG=info \
  --entrypoint /cargo-target/release/kataglyphis_cat_webrtc "$IMAGE" \
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