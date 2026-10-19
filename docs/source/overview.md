# Overview

OmniAccelerANT is a Flutter frontend over native Rust/C++ inference and GStreamer media pipelines.

## Architecture at a Glance

- **Frontend:** Flutter/Dart app
- **Native core:** Rust/C++ components exposed via `flutter_rust_bridge`
- **Media stack:** GStreamer pipelines for camera ingest and WebRTC transport
- **Targets:** Linux, Windows, Android, Web, and embedded Linux variants
- **ObservANT:** a `.deb`, AppImage, flatpak or Windows MSI that streams a camera to any browser,
  spots cats with a detection model, logs their visits, keeps a picture and a 10 s video of each
  arrival, and posts them to a webhook such as Home Assistant's. Its web page has a Camera page
  that turns the picture, sets how sure detection must be and renames the camera while it runs.
  It runs on x64 PCs, the Raspberry Pi 3, 4 and 5, and the SpacemiT X100 (riscv64).

## Repository Structure

| Path | Purpose |
|------|---------|
| `lib/` | Flutter/Dart application code |
| `android/`, `linux/`, `windows/`, `web/` | Platform integration layers (`ios/` and `macos/` hold only generated plugin registrants — neither is a target) |
| `scripts/` | Build, tooling, and documentation automation |
| `docs/source/` | Human-authored guide pages included in generated docs |
| `doc/api/` | Generated API and guide output: `scripts/linux/generate-docs.sh` runs the SDK's `dart doc`, `Build-Windows.ps1` a pub-activated `dartdoc` (see [Getting Started](getting-started.md#6-build-api-docs)) |
| `packages/kataglyphis_native_inference` | Flutter plugin (Android, Linux, Windows) that bridges the native GStreamer/inference code to Dart; on Linux and Windows it links the C++ inference core. Plain files and a `pubspec.yaml` path dependency, not a submodule |
| `third_party/OxidANT` | Rust core (`oxidant` crate), bridged into `lib/src/rust/` by `flutter_rust_bridge` |
| `third_party/AccelerANTgine` | The C++ inference core the plugin builds against |
| `third_party/ANTfrastructure` | Shared build images, container actions, and CI helpers |
| `third_party/ANThology` | Shared Flutter/Dart code (`anthology` package), a path dependency in `pubspec.yaml` |

## Core Design Goals

1. **Cross-platform parity** where practical, across desktop, web and embedded targets.
2. **Fast iteration**: scriptable local workflows, containerized environments.
3. **Clear API boundaries** between UI and inference logic.
4. **Operational transparency**: documented platform and streaming workflows.

## Feature Status

From the README (2026-10-19). ✔️ done (implemented and tested), 🔶 in progress, ❌ not started
(planned), N/A not applicable to the platform.

### Core Features

| Category | Feature | Win x64 | Linux x64 | Linux ARM64 | Linux RISC-V | Android |
|----------|---------|:-------:|:---------:|:-----------:|:------------:|:-------:|
| **Camera Streaming** | GStreamer WebRTC Livestream | ✔️ | ✔️ | ✔️ | ✔️ | N/A |
| | Local Webcam ONNX Inference (Rust) | ✔️ | 🔶 | 🔶 | ❌ | ❌ |
| **Supported Cameras** | USB Devices | ✔️ | ✔️ | ✔️ | ✔️ | N/A |
| | Raspberry Pi Camera | N/A | N/A | ✔️ | N/A | N/A |
| | Native Camera API | N/A | N/A | N/A | N/A | ✔️ |

### Infrastructure & Build

| Category | Feature | Win x64 | Linux x64 | Linux ARM64 | Linux RISC-V | Android |
|----------|---------|:-------:|:---------:|:-----------:|:------------:|:-------:|
| **Containerization** | Builds in ANTfrastructure `:latest` (linux) / `:winamd64` (windows) images; the Windows arm64 app cross-builds its natives in the hub's `:winarm64` bundle and its Flutter part natively on `windows-11-arm` | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| **Native Integration** | GTK Integration | N/A | ✔️ | ✔️ | ❌ | N/A |
| | Win32 API | ✔️ | N/A | N/A | N/A | N/A |
| | Android NDK | N/A | N/A | N/A | N/A | ✔️ |
| **Bridge Layer** | flutter_rust_bridge | ✔️ | ✔️ | ✔️ | ❌ | ✔️ |
| **Compiler** | Clang-CL | ✔️ | N/A | N/A | N/A | N/A |
| | GCC/Clang | N/A | ✔️ | ✔️ | ✔️ | ✔️ |

### Testing & Quality Assurance

| Category | Feature | Win x64 | Linux x64 | Linux ARM64 | Linux RISC-V | Android |
|----------|---------|:-------:|:---------:|:-----------:|:------------:|:-------:|
| **Unit Testing** | Advanced unit testing | 🔶 | 🔶 | 🔶 | 🔶 | 🔶 |
| **Performance** | Advanced performance testing | 🔶 | 🔶 | 🔶 | 🔶 | 🔶 |
| **Security** | Advanced fuzz testing | 🔶 | 🔶 | 🔶 | 🔶 | 🔶 |

### Frontend Platforms

| Category | Feature | Win x64 | Linux x64 | Linux ARM64 | Linux RISC-V | Android |
|----------|---------|:-------:|:---------:|:-----------:|:------------:|:-------:|
| **Flutter UI** | Flutter Web Support | ✔️ | ✔️ | ✔️ | ✔️ | ✔️ |
| | Flutter Desktop | ✔️ | ✔️ | ✔️ | ❌ | N/A |
| | Flutter Mobile | N/A | N/A | N/A | N/A | ✔️ |

On RISC-V only ObservANT builds (its `.deb`, natively on the X100); no lane builds the Flutter
app for it, so the app-side rows read ❌ there. The Rust camera view runs on Windows and Linux
only.

### Platform Summary

| Platform | Architecture | Status | Notes |
|----------|-------------|:------:|-------|
| **Windows** | x86-64 | ✔️ | Built with clang-cl, Win32 integration; every release has an MSI, a signed MSIX and a zip |
| **Windows** | ARM64 | 🔶 | Hybrid lane (`windows-arm64.yml`): natives cross-built in `:winarm64`, the Flutter app built natively on `windows-11-arm`. Every release has an MSI, a signed MSIX and a zip, which install, start and uninstall on that device (since 2.2.0); ObservANT's arm64 MSI installs there and its model finds a cat in a photo. No camera frame has run on arm64 yet |
| **Linux** | x86-64 | ✔️ | GTK app; every release has a `.deb`, an AppImage, a flatpak and a tarball, which carry their own libraries: the family's own GStreamer and its plugins (never the distro's), and glibc for distros older than the build image |
| **Linux** | ARM64 | ✔️ | Raspberry Pi 3, 4, 5 and Zero 2 W; the Zero streams without detection, since 512 MB is not enough for the Rust producer, and a Pi 3 detects at about 2 s per look |
| **Linux** | RISC-V | 🔶 | No CI lane in this repo: the `:latest` image index carries a riscv64 variant, and OxidANT tests its crates under QEMU. The ObservANT `.deb` builds natively on a SpacemiT X100 and runs there with a USB webcam (2026-10-13). |
| **Android** | ARM64 | 🔶 | Native camera, NDK integration; the app targets `arm64-v8a` only. The image's Android GStreamer/ONNX/OpenCV prebuilts became `arm64-v8a` on 2026-09-11, so the old `incompatible with aarch64linux` link failure is gone, and since CI stopped running CodeQL (2026-09-17) the lane builds the plain APK, native link and the plugin's JVM test included (AGENTS.md § 4). |

## Where to Continue

- Setup and first run: [Getting Started](getting-started.md)
- Target-specific builds: [Platform Guides](platforms.md)
- Streaming and inference pipelines: [Camera Streaming](camera-streaming.md)
- ObservANT, installed and wired to a phone: [ObservANT package](camera-streaming.md#the-observant-package)
  and [Home Assistant](camera-streaming.md#home-assistant)

## Literature

Tutorials, documentation and resources (from the README, 2026-10-19):

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
- [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`), the search tool for this tree
- [tmux](https://github.com/tmux/tmux/wiki)
- [zellij](https://zellij.dev/)
- [psmux](https://github.com/marlocarlo/psmux)

### Android
- [Gstreamer+flutter+android](https://github.com/hpdragon1618/flutter_gstreamer_player)
