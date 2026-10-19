# OmniAccelerANT — Documentation Hub

## Start Here

- **New contributors:** [Getting Started](source/getting-started.md)
- **Deployment targets:** [Platform Guides](source/platforms.md)
- **Streaming + inference pipelines:** [Camera Streaming](source/camera-streaming.md)
- **README navigation:** [Readmes](source/readmes.md)
- **Team workflows:** [Project Operations](source/project-operations.md)

## Documentation Map

| Area | Purpose |
|------|---------|
| [Overview](source/overview.md) | Architecture, repository layout, design goals, feature status per platform, literature. |
| [Getting Started](source/getting-started.md) | Local setup, the lanes CI runs, first run, verification checks. |
| [Platforms](source/platforms.md) | Linux, Windows, Android, Raspberry Pi and Web instructions. |
| [Camera Streaming](source/camera-streaming.md) | The installable ObservANT, GStreamer WebRTC pipelines, the Rust cat-detection producer. |
| [ESP32-S3 Companion & Camera](source/esp32.md) | The Rust companion firmware, the ESP32-S3-EYE camera with on-device cat detection, the Device page. |
| [Testing](source/testing.md) | What each kind of test proves, what the app's Dart suite checks, the known gaps. |
| [Readmes](source/readmes.md) | Links to the relevant README entry points. |
| [Project Operations](source/project-operations.md) | Build/test/doc workflows, release notes, contribution flow. |
| [Upgrade Guide](source/upgrade-guide.md) | Dependency and bridge upgrades. |

## What This Project Delivers

AI inference on desktop, web and embedded devices: a Flutter/Dart frontend over a Rust/C++
inference core (`flutter_rust_bridge`), GStreamer/WebRTC camera streaming, and container and
native build scripts per platform for a reproducible setup.

## Read in This Order

[Overview](source/overview.md) → [Getting Started](source/getting-started.md) →
[Platforms](source/platforms.md) → [Camera Streaming](source/camera-streaming.md) →
[Project Operations](source/project-operations.md)
