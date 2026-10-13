<div align="center">
  <a href="https://jonasheinle.de">
    <img src="images/logo.png" alt="logo" width="200" />
  </a>

  <h1>OmniAccelerANT</h1>

  <h4>An inference engine with Flutter/Dart frontend and Rust/C++ backend, showcasing Gstreamer capabilities enhanced with AI. Read further if you are interested in cross platform AI inference. </h4>

</div>

[![Linux x64 · build + test](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/linux-x64.yml/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/linux-x64.yml) [![Linux arm64 · build + test](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/linux-arm64.yml/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/linux-arm64.yml) [![Windows x64 · build + test](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/windows-x64.yml/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/windows-x64.yml) [![Windows arm64 · cross build + test](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/windows-arm64.yml/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/windows-arm64.yml) [![Web · build + test](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/web.yml/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/web.yml)  
 [![Android · build + test](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/android.yml/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/android.yml)[![Automatic Dependency Submission](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/dependency-graph/auto-submission/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/dependency-graph/auto-submission)
[![Dependabot Updates](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/dependabot/dependabot-updates)
[![TopLang](https://img.shields.io/github/languages/top/Kataglyphis/OmniAccelerANT)]()
[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.com/donate/?hosted_button_id=BX9AVVES2P9LN)
[![Twitter](https://img.shields.io/twitter/follow/Cataglyphis_?style=social)](https://twitter.com/Cataglyphis_)
[![YouTube](https://img.shields.io/youtube/channel/subscribers/UC3LZiH4sZzzaVBCUV8knYeg?style=social)](https://www.youtube.com/channel/UC3LZiH4sZzzaVBCUV8knYeg)

[**Official homepage**](https://kataglyphisinferenceengine.jonasheinle.de)

## Overview

OmniAccelerANT bundles a Flutter/Dart frontend, a Rust/C++ inference core, and a rich set of camera streaming pipelines powered by GStreamer. The repository acts as an end-to-end reference for building cross-platform inference products that target desktop, web, and embedded devices.

## Highlights & Key Features – OmniAccelerANT

### 🌟 Highlights

- 🎨 **GStreamer native GTK integration** – Leveraging users to write beautiful Linux AI inference apps.
- 🐱 **An installable cat cam** – a `.deb`, AppImage, flatpak or Windows MSI that streams a camera to any browser, spots cats with a YOLO model on a Raspberry Pi 5, logs their visits, and keeps a picture and a 10 s video of each arrival; Home Assistant can put those on a phone ([Live cat detection stream](#live-cat-detection-stream-linux--raspberry-pi)).
- 📹 **GStreamer WebRTC livestreaming** with ready-to-use pipelines for USB, Raspberry Pi, and Orange Pi cameras.
- 🌉 **flutter_rust_bridge integration** – Ensures a seamless API boundary between Dart UI and Rust logic.
- 🐳 **Containerized development flow** plus native instructions for Windows, Linux, web. For details in my build environment look into [ANTfrastructure](https://github.com/Kataglyphis/ANTfrastructure). On Windows the container engine is [Stevedore](https://github.com/slonopotamus/stevedore) and build containers run with `--isolation process` (full host CPU count) — see [docs/source/platforms.md](docs/source/platforms.md).

### 📊 Feature Status Matrix

#### Core Features

| Category | Feature | Win x64 | Linux x64 | Linux ARM64 | Linux RISC-V | Android |
|----------|---------|:-------:|:---------:|:-----------:|:------------:|:-------:|
| **Camera Streaming** | 📹 GStreamer WebRTC Livestream | ✔️ | ✔️ | ✔️ | ✔️ | N/A |
| | 🧠 Local Webcam ONNX Inference (Rust) | ✔️ | 🔶 | 🔶 | 🔶 | 🔶 |
| **Supported Cameras** | 🔌 USB Devices | ✔️ | ✔️ | ✔️ | ✔️ | N/A |
| | 🍓 Raspberry Pi Camera | N/A | ✔️ | ✔️ | ✔️ | N/A |
| | 🟠 Orange Pi Camera | N/A | ❌ | ❌ | ❌ | N/A |
| | 📱 Native Camera API | N/A | N/A | N/A | N/A | ✔️ |

#### Infrastructure & Build

| Category | Feature | Win x64 | Linux x64 | Linux ARM64 | Linux RISC-V | Android |
|----------|---------|:-------:|:---------:|:-----------:|:------------:|:-------:|
| **Containerization** | 🐳 Builds in ANTfrastructure `:latest` (linux) / `:winamd64` (windows) images; the Windows arm64 app cross-builds its natives in the hub's `:winarm64` bundle and its Flutter part natively on `windows-11-arm` | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| **Native Integration** | 🎨 GTK Integration | N/A | ✔️ | ✔️ | ✔️ | N/A |
| | 🪟 Win32 API | ✔️ | N/A | N/A | N/A | N/A |
| | 🤖 Android NDK | N/A | N/A | N/A | N/A | ✔️ |
| **Bridge Layer** | 🌉 flutter_rust_bridge | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| **Compiler** | 🔧 Clang-CL | ✔️ | N/A | N/A | N/A | N/A |
| | 🔧 GCC/Clang | N/A | ✔️ | ✔️ | ✔️ | ✔️ |

#### Testing & Quality Assurance

| Category | Feature | Win x64 | Linux x64 | Linux ARM64 | Linux RISC-V | Android |
|----------|---------|:-------:|:---------:|:-----------:|:------------:|:-------:|
| **Unit Testing** | 🧪 Advanced unit testing | 🔶 | 🔶 | 🔶 | 🔶 | 🔶 |
| **Performance** | ⚡ Advanced performance testing | 🔶 | 🔶 | 🔶 | 🔶 | 🔶 |
| **Security** | 🔍 Advanced fuzz testing | 🔶 | 🔶 | 🔶 | 🔶 | 🔶 |

#### Frontend Platforms

| Category | Feature | Win x64 | Linux x64 | Linux ARM64 | Linux RISC-V | Android |
|----------|---------|:-------:|:---------:|:-----------:|:------------:|:-------:|
| **Flutter UI** | 🦋 Flutter Web Support | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| | 💻 Flutter Desktop | ✔️ | ✔️ | ✔️ | ✔️ | N/A |
| | 📱 Flutter Mobile | N/A | N/A | N/A | N/A | ✔️ |

---

#### Platform Summary

| Platform | Architecture | Status | Notes |
|----------|-------------|:------:|-------|
| 🪟 **Windows** | x86-64 | ✔️ | Built with clang-cl, Win32 integration |
| 🪟 **Windows** | ARM64 | 🔶 | Hybrid lane (`windows-arm64.yml`): natives cross-built in `:winarm64`, the Flutter app built natively on `windows-11-arm`. On the device every import resolves and the app starts with a window; no camera frame or inference has run on arm64 yet |
| 🐧 **Linux** | x86-64 | ✔️ | Full GTK support, Docker ready |
| 🐧 **Linux** | ARM64 | ✔️ | SBC optimized (RPi, OPi support) |
| 🐧 **Linux** | RISC-V | 🔶 | Emerging architecture support. No CI lane in this repo — the `:latest` image index carries a riscv64 variant, and OxidANT tests its crates under QEMU. The cat cam `.deb` builds natively on a riscv64 board and runs there (2026-10-13). |
| 🤖 **Android** | ARM64 | 🔶 | Native camera, NDK integration. The app targets `arm64-v8a` only. The image's Android GStreamer/ONNX/OpenCV prebuilts became `arm64-v8a` on 2026-09-11, so the old `incompatible with aarch64linux` link failure is gone, and since CI stopped running CodeQL (2026-09-17) the lane builds the plain APK — native link and the plugin's JVM test included (AGENTS.md § 4). |

---

**Legend:**
- ✔️ **Completed** - Feature fully implemented and tested
- 🔶 **In Progress** - Active development underway
- ❌ **Not Started** - Planned but not yet begun
- **N/A** - Not applicable for this platform

## Quick Start

1. Clone the repository with submodules:  
  > **__NOTE:__**
  > On Windows I use [Git Bash](https://git-scm.com/install/windows) instead of  
  > Powershell or cmd
   ```bash
   git clone --recurse-submodules --branch develop https://github.com/Kataglyphis/OmniAccelerANT.git
   cd OmniAccelerANT
   ```
2. Initialize submodules if needed.  
   If u used `--recurse-submodules` while cloning you are already good.  
   Otherwise you can use this :smile:
   ```bash
   git submodule update --init --recursive
   ```

Refer to the detailed docs below for platform-specific requirements, camera streaming pipelines, and deployment workflows.

3. Build the app. **Every lane runs containerized, and local runs invoke the
   same script CI invokes** — the exact commands, presets and switches are in
   [AGENTS.md § 5](AGENTS.md#5-build-run-test):

   | Lane | What CI runs | Locally |
   |---|---|---|
   | Windows (amd64) | `scripts/windows/Build-Windows.ps1` | the same script, in the same image |
   | Linux native (amd64 / arm64) | `scripts/linux/ci/ci-container-run-native-linux.sh` | `Invoke-LinuxLane.ps1` |
   | Android | `scripts/linux/ci/ci-container-run-android.sh` | `Invoke-LinuxLane.ps1 -Lane android` |
   | Web | `scripts/linux/ci/ci-container-run-web-linux.sh` | `Invoke-LinuxLane.ps1 -Lane web` |

   The Linux entries go through ANTfrastructure's `run-in-linux-container` action
   in CI and Rancher Desktop's `nerdctl` locally; inside the container the two
   are identical, down to the argument list. Reproduce a CI failure locally
   before pushing — that is the whole point of the arrangement.

   The native Linux lane takes an opt-in linker,
   `Invoke-LinuxLane.ps1 -Env KATAGLYPHIS_LINKER=lld` (or `mold`). It is off in CI;
   what each one buys is in [AGENTS.md § 5](AGENTS.md#5-build-run-test).

   Building the Linux lane locally on a Windows host has host-side
   prerequisites — Rancher Desktop's engine, the drive the repo lives on being
   visible to *containerd's own* mount namespace, and QEMU binfmt registered
   for an arm64 run. The lane commands are in
   [AGENTS.md § 5](AGENTS.md#5-build-run-test), "The Linux lane, locally",
   which links the binfmt and mount fixes; the reasoning behind them is
   ANTfrastructure's, in
   [`rancher-desktop-linux-containers.md`](third_party/ANTfrastructure/docs/rancher-desktop-linux-containers.md).
   Both prerequisites are lost on a VM restart, and skipping either is silent:
   you get a bind mount that resolves and is empty, or an arm64 container
   running x86-64 binaries.

### Live cat detection stream (Linux / Raspberry Pi)

`third_party/OxidANT`'s `kataglyphis_cat_webrtc` captures a camera, runs the
YOLO ONNX model for cats (COCO class 15), burns the boxes into the frames and
publishes them as a WebRTC stream that the Flutter web app's **Stream** page
consumes.

**The installable cat cam (Linux .deb, AppImage or flatpak).** In a privileged
`:latest`, with the web lane's `build/web`, run `scripts/linux/cat-stream/package-catcam.sh
--web-root build/web`. That builds `out/omni-accelerant-catcam_<version>_<arch>.deb`, an
`.AppImage` and a `.flatpak`; `web.yml` uploads all three for x64 and arm64. On a riscv64
board, run it in that board's own `:latest`: it builds the `.deb` and a tarball, as flatpak has
no riscv64 runtime.
- `sudo apt install ./omni-accelerant-catcam_*.deb`, or `sudo ./omni-accelerant-catcam-*.AppImage
  --install` on any other distro, installs a systemd service that starts at boot.
- `flatpak install ./omni-accelerant-catcam-*.flatpak` runs in a sandbox instead. It
  starts at sign-in once you have run it, and takes USB cameras only.
- Open `http://<host>:8080/` from a browser on the network. Under the video the page
  says whether a cat is in view, or when one was last seen, lists its latest visits
  with how long each lasted, and shows the picture of its last arrival, with a link to
  its video once that is encoded and to the four videos kept before it.
- The **Camera** page beside it changes the cat cam while it runs: ⟲ and ⟳ turn the
  picture a quarter each way, a slider sets how sure detection must be before a cat counts,
  and the name can be changed. A preview shows the result, and a table what the camera
  runs. The cat cam keeps all three across restarts.
- `http://<host>:8080/healthz` says which camera is live, when a cat was last seen,
  how many visits it counted and how long the latest 20 lasted; `/snapshot.jpg` is the
  current picture, boxes included, `/arrival.jpg` the frame the last arrival was
  confirmed on, and `/arrival.mp4` that arrival as a 10 s video, from 3 s before it.
  The visits, that frame and that video survive a restart.
- Set `notify_url` in the settings and the service POSTs every arrival, departure and
  finished video there as JSON, for example to a Home Assistant webhook.
  [camera-streaming.md § Home Assistant](docs/source/camera-streaming.md#home-assistant) has an automation
  that sends each arrival to a phone with its picture and then its video, and sensors
  for visits per day and an alert when the cat cam stops answering.
- A second cat cam is another install on another board: give each its own `name` and
  webhook, and one Home Assistant automation serves both (*More than one cat cam* there).
- The service picks a Raspberry Pi camera when one is attached, else a USB
  webcam.
- The settings live in `/etc/omni-accelerant/catcam.toml`, and `systemctl
  disable --now omni-catcam` turns autostart off.

Verified on amd64 in `:latest`, and running on two Raspberry Pi 5s, one with a Camera
Module 2 (imx219) and one with a Camera Module 3 (imx708), and on a SpacemiT riscv64 board
with a Logitech C270 (2026-10-13).
On Windows, `scripts\windows\cat-stream\Package-CatCam.ps1` (in `:winamd64`) builds an
MSI, and with `-Msix` a signed MSIX. Each installs the cat cam, starts it at every logon,
opens the firewall to the network, and streams the same page. Both are tested in the
image and on a Windows 11 PC; a camera on Windows is still untested. Details:
[docs/source/camera-streaming.md § The cat cam package](docs/source/camera-streaming.md#the-cat-cam-package).

**By hand.** One native Linux host does everything, a Raspberry Pi included:

```bash
# 1. the producer (in third_party/OxidANT); USB cameras use --v4l2. ONNX Runtime
#    must be the image's chain build - OxidANT's loader refuses any other copy
#    (2026-09-23) - so this runs in the :latest image, where that path is the
#    loader's own fallback too
cargo build --release -p kataglyphis_cat_webrtc
ORT_DYLIB_PATH=/usr/local/lib/onnxruntime-cpu/lib/libonnxruntime.so \
  target/release/kataglyphis_cat_webrtc --v4l2 /dev/video0

# 2. once: the web frontend. web/pkg/ is a generated frb artefact (gitignored),
#    so this is the same sequence the web CI lane runs.
rustup toolchain install nightly --component rust-src --target wasm32-unknown-unknown
cargo install --locked --version 2.13.0 flutter_rust_bridge_codegen  # the pin in third_party/OxidANT/Cargo.toml
flutter_rust_bridge_codegen build-web --release --rust-root third_party/OxidANT
flutter build web --release --wasm --no-web-resources-cdn

# 3. HTTPS + COOP/COEP + the /webrtc-ws proxy in front of both (:8444);
#    --http serves the same on plain HTTP, with no certificate
scripts/linux/cat-stream/serve.sh
```

Open `https://<host>:8444/` — on the phone too, accepting the self-signed
certificate warning — or start `serve.sh --http` and open `http://<host>:8444/`
with no warning: the Stream page needs no secure context, and the web app boots
without its optional Rust core where a browser refuses it there. `signalingServerUrl` in
`assets/settings/webrtc_settings.json` is host-relative (`/webrtc-ws`), so the
web client connects to the origin it was served from and no hostname is baked
into the build. On a Raspberry Pi 5 with the CSI camera,
`third_party/OxidANT/scripts/linux/cat-stream/run-producer-pi.sh --build`
replaces step 1 — it lives in OxidANT, which owns the producer crate — and adds
`--libcamera` plus the host-libcamera container wiring the Pi 5 kernel needs. A
Pi Zero 2 W runs the same image with that swap and a `gst-launch` no-AI stream
on top of it (512 MB is not enough for the Rust producer), and a RISC-V SoC
runs the riscv64 variant natively with a USB webcam via `--v4l2`. A Raspberry
Pi 4 (or any VC4/unicam Pi) runs the same host-libcamera swap with the Rust
producer and inference; a camera mounted upside down is `--rotate 180`. In the
deployed shape each board runs its own copy of this web build and `serve.sh`,
so its own camera appears on `https://<board>:8444/` (the per-board recipes are
in the doc below) — and a board is started with one command, its local
`~/cat-cam.sh start` (autostart is opt-in: only the Zero has a systemd unit); `serve.sh --producer-host
<board-ip>` is only for looking at another board from the dev host — use its IP
(nginx resolves the name once at startup) and open that instance's port there
too. Pipeline details, flags and troubleshooting:
[docs/source/camera-streaming.md](docs/source/camera-streaming.md).

### Browse the API docs locally

Generate the site into `doc/api`, then serve it. Use the pub-activated
`dartdoc`, **not** the SDK-bundled `dart doc`: dartdoc 9.0.4 (bundled with
several Flutter SDKs, the Windows build image's among them before it moved to
Flutter 3.47.4) crashes on any Flutter app with a `_stripDocImports` RangeError;
≥ 9.0.9 fixes it. Both images carry Flutter 3.47.4 now (CI, 2026-09-25), whose
bundled `dart doc` the Linux lane's `generate-docs.sh` runs without trouble.

`scripts/windows/Build-Windows.ps1` already does this for you as its
"Generate API Docs" step (skip it with `-SkipDocs`); the commands below are for
generating and serving the site by hand.

```bash
dart pub global activate dartdoc      # pulls >= 9.0.9
dart pub global run dartdoc --output doc/api
dart pub global activate dhttpd
export PATH="$PATH:$HOME/.pub-cache/bin"
dhttpd --path doc/api --host 127.0.0.1 --port 8080
```

On PowerShell the pub-cache `bin` goes on `PATH` differently:

```powershell
$env:Path += ";$env:USERPROFILE\AppData\Local\Pub\Cache\bin"
```

Then open <http://127.0.0.1:8080>.

## Documentation

| Topic | Location | Description |
|-------|----------|-------------|
| Overview & architecture | [docs/source/overview.md](docs/source/overview.md) | What the project is, the architecture at a glance, and what each top-level directory holds. |
| Getting Started | [docs/source/getting-started.md](docs/source/getting-started.md) | Environment prerequisites, installation, and run commands. |
| Platform Guides | [docs/source/platforms.md](docs/source/platforms.md) | Container, Windows, Raspberry Pi, and web build instructions — incl. the Windows container troubleshooting table (Dev Drive, pkg-config, rustup/Cargokit, Debug-preset pitfalls). |
| Agent / contributor guide | [AGENTS.md](AGENTS.md) | Build workflow, container pitfalls, and quality gates for coding agents and new contributors. |
| Known cleanups | [BACKLOG.md](BACKLOG.md) | Refactors and verification gaps this repo knows about but has not done yet, in the format ANTfrastructure's agentic loop consumes. |
| Camera Streaming | [docs/source/camera-streaming.md](docs/source/camera-streaming.md) | The installable cat cam and its Home Assistant notifications, the Rust webcam path (Windows and Linux; a test-pattern frame crosses it on every native lane run), and the GStreamer WebRTC pipelines. |
| Upgrade guide | [docs/source/upgrade-guide.md](docs/source/upgrade-guide.md) | How to keep things up-to-date. |
| Dependency upgrades | [third_party/ANTfrastructure/docs/dependency-updates.md](third_party/ANTfrastructure/docs/dependency-updates.md) | Renovate run as a local CLI. Submodule upgrades go through `bash scripts/linux/renovate-local.sh` (add `--apply` to move the gitlinks), not by hand; `--apply` also rewrites the manifests it reported, `pubspec.yaml` included (AGENTS.md § 5). |

The site CI publishes — the API docs plus every guide in `docs/source` — comes from `bash scripts/linux/generate-docs.sh` (AGENTS.md § 6), which stages the guides its `DARTDOC_BUILD_GUIDES` array lists.

## Tests

Every test runs on every lane that can host it: the app's and the plugin's Dart
suites, the plugin's gtest and C ABI check, the bundle's runtime closure and
ONNX Runtime proof, a 20 s launch smoke and, on Linux, the integration test under
Xvfb. The per-lane table is [AGENTS.md § 5](AGENTS.md#5-build-run-test), *What
each lane tests*; the open gaps are tracked in [BACKLOG.md](BACKLOG.md).

The app's own Dart suite (`test/`) checks, among the rest:
- every main page laid out at phone, tablet and desktop size, on a phone with its system
  font at 150 % and 200 %, and on a desktop at 200 %, with the real font
  (`app_layout_test.dart`);
- the camera stream's state across remounts, page changes, lost signalling and failed
  sessions (`webrtc_stream_controller_test.dart`);
- the cat status line, its visits, its arrival picture and video, and the earlier videos
  (`cat_status_test.dart`);
- the Camera page: what it reads from a cat cam, what each button, the slider and the
  name field send, a refused change, and the page off a cat cam (`camera_settings_test.dart`);
- the native Stream page's calls to the C++ plugin, its camera fallback, its buttons and
  its error messages, on Linux, Android (camera permission included), macOS and the
  rest, against a fake plugin (`stream_page_native_test.dart`); Windows and Linux with the
  Rust features handing the camera to the Rust view (`stream_page_rust_test.dart`); and
  the Rust camera view's calls to the core, against a fake core (`rust_webcam_view_test.dart`);
- the GStreamer pipeline strings, which otherwise fail only on a machine with a camera
  (`gstreamer_pipeline_builder_test.dart`);
- the settings files: a malformed key named in the error, and the web's signalling URL
  resolved against the page (`webrtc_settings_test.dart`, `settings_asset_paths_test.dart`);
- the web booting without the Rust core, and native refusing to (`rust_core_test.dart`);
- the About page's SQLite line and its error text (`sqlite3_healthcheck_widget_test.dart`);
- what no build step checks: the bridge's versions, the sqlite3 wasm, 8-bit icons
  (`pinned_artefacts_test.dart`), and that every social link has an icon.

The native Linux lane measures how much of `lib/` these reach and fails below a floor
(96.5 % on 2026-10-13; `check-dart-coverage.sh`).

`flutter test` in the `:latest` image runs it in under a minute
([AGENTS.md § 5](AGENTS.md#5-build-run-test), *The Dart gate in 23 seconds*).

## Roadmap

Planned work lives in [BACKLOG.md](BACKLOG.md), in the format ANTfrastructure's
agentic loop consumes. The aspirational `docs/source/roadmap.md` that used to sit
here was never filled in and was deleted on 2026-09-15; git history keeps it.

## Contributing

Contributions are what make the open-source community amazing. Any contributions are **greatly appreciated**.

1. Fork the project.
2. Create your feature branch (`git checkout -b feature/AmazingFeature`).
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

## License

MIT (see [here](LICENSE))

## Acknowledgements

Thanks to the open-source community and all contributors!

## Literature

Helpful tutorials, documentation, and resources:

### Multimedia
- [GStreamer](https://gstreamer.freedesktop.org/)

### Rust
- [GStreamer-rs tutorial](https://gstreamer.freedesktop.org/documentation/rswebrtc/index.html?gi-language=c)
- [gst-plugins-rs](https://github.com/GStreamer/gst-plugins-rs)
- [GStreamer WebRTC](https://github.com/GStreamer/gst-plugins-rs/tree/main/net/webrtc)

### Raspberry Pi
- [GStreamer on Raspberry Pi](https://www.raspberrypi.com/documentation/computers/camera_software.html)
- [libcamera](https://libcamera.org/)
- [libcamera on Raspberry Pi](https://github.com/raspberrypi/libcamera)

### CMake/C++
- [clang-cl](https://clang.llvm.org/docs/MSVCCompatibility.html)

### Flutter/Dart
- [Linux Native Textures](https://github.com/flutter/flutter/blob/master/examples/texture/lib/main.dart)
- [flutter_rust_bridge](https://cjycode.com/flutter_rust_bridge/)
- [Flutter on RISCV](https://github.com/ardera/flutter-ci/)

### Protocols
- [WebRTC](https://webrtc.org/?hl=de)

### Tooling
- [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`), the search tool for this tree:
  `winget install --id BurntSushi.ripgrep.MSVC -e --scope user`, or `apt install ripgrep`
- [tmux](https://github.com/tmux/tmux/wiki)
- [zellij](https://zellij.dev/)
- [psmux](https://github.com/marlocarlo/psmux)

### Android
- [Gstreamer+flutter+android](https://github.com/hpdragon1618/flutter_gstreamer_player)

## Contact

**Jonas Heinle**  
Twitter: [@Cataglyphis_](https://twitter.com/Cataglyphis_)  
Email: cataglyphis@jonasheinle.de

**Project Links:**
- GitHub: [OmniAccelerANT](https://github.com/Kataglyphis/OmniAccelerANT)
- Homepage: [Official Site](https://kataglyphisinferenceengine.jonasheinle.de)
