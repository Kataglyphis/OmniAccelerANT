# Overview

Kataglyphis Inference Engine combines a Flutter frontend with native Rust/C++ inference and GStreamer-powered media pipelines.

## Architecture at a Glance

- **Frontend:** Flutter/Dart app for cross-platform UI
- **Native core:** Rust/C++ components exposed via `flutter_rust_bridge`
- **Media stack:** GStreamer pipelines for camera ingest and WebRTC transport
- **Targets:** Linux, Windows, Android, Web, and embedded Linux variants

## Repository Structure

| Path | Purpose |
|------|---------|
| `lib/` | Flutter/Dart application code |
| `android/`, `ios/`, `linux/`, `windows/`, `macos/`, `web/` | Platform integration layers |
| `scripts/` | Build, tooling, and documentation automation |
| `docs/source/` | Human-authored guide pages included in generated docs |
| `doc/api/` | Generated API and guide output from `dart doc` |
| `ExternalLib/` | External and related repositories/submodules |

## Core Design Goals

1. **Cross-platform parity** where practical across desktop, web, and embedded targets.
2. **Fast iteration** with scriptable local workflows and containerized environments.
3. **Clear API boundaries** between UI and inference logic.
4. **Operational transparency** through documented platform and streaming workflows.

## Where to Continue

- Setup and first run: [Getting Started](getting-started.md)
- Target-specific builds: [Platform Guides](platforms.md)
- Streaming and inference pipelines: [Camera Streaming](camera-streaming.md)