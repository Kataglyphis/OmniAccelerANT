# Overview

OmniAccelerANT combines a Flutter frontend with native Rust/C++ inference and GStreamer-powered media pipelines.

## Architecture at a Glance

- **Frontend:** Flutter/Dart app for cross-platform UI
- **Native core:** Rust/C++ components exposed via `flutter_rust_bridge`
- **Media stack:** GStreamer pipelines for camera ingest and WebRTC transport
- **Targets:** Linux, Windows, Android, Web, and embedded Linux variants
- **The cat cam:** a `.deb`, AppImage, flatpak or Windows MSI that streams a camera to
  any browser, spots cats with a YOLO model, logs their visits, keeps a picture and a
  10 s video of each arrival, and posts them to a webhook such as Home Assistant's. Its
  web page has a Camera page that turns the picture, sets how sure detection must be and
  renames the camera while it runs. It runs on x64 PCs, the Raspberry Pi 4 and 5, and the
  SpacemiT X100 (riscv64).

## Repository Structure

| Path | Purpose |
|------|---------|
| `lib/` | Flutter/Dart application code |
| `android/`, `linux/`, `windows/`, `web/` | Platform integration layers (`ios/` and `macos/` hold only generated plugin registrants — neither is a target) |
| `scripts/` | Build, tooling, and documentation automation |
| `docs/source/` | Human-authored guide pages included in generated docs |
| `doc/api/` | Generated API and guide output (pub-activated `dartdoc`, not the SDK-bundled `dart doc` — see the README) |
| `packages/kataglyphis_native_inference` | Flutter plugin (Android, Linux, Windows) that bridges the native GStreamer/inference code to Dart — on Linux and Windows it links the C++ inference core — plain files and a `pubspec.yaml` path dependency, not a submodule |
| `third_party/OxidANT` | Rust core (`oxidant` crate), bridged into `lib/src/rust/` by `flutter_rust_bridge` |
| `third_party/AccelerANTgine` | The C++ inference core the plugin builds against |
| `third_party/ANTfrastructure` | Shared build images, container actions, and CI helpers |
| `third_party/ANThology` | Shared Flutter/Dart code (`anthology` package), a path dependency in `pubspec.yaml` |

## Core Design Goals

1. **Cross-platform parity** where practical across desktop, web, and embedded targets.
2. **Fast iteration** with scriptable local workflows and containerized environments.
3. **Clear API boundaries** between UI and inference logic.
4. **Operational transparency** through documented platform and streaming workflows.

## Where to Continue

- Setup and first run: [Getting Started](getting-started.md)
- Target-specific builds: [Platform Guides](platforms.md)
- Streaming and inference pipelines: [Camera Streaming](camera-streaming.md)
- The cat cam, installed and wired to a phone: [The cat cam package](camera-streaming.md#the-cat-cam-package)
  and [Home Assistant](camera-streaming.md#home-assistant)
