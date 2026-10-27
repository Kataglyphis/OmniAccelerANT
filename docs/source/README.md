<h1 align="center">
  OmniAccelerANT Docs
</h1>

<p align="center">
  The guides for the Kataglyphis inference stack: Flutter, Rust/C++ and GStreamer.
</p>

---

## Documentation Map

| Topic | Description |
|-------|-------------|
| [Overview](overview.md) | ObservANT, targets, the repository's structure and design goals, feature status per platform, literature. |
| [Getting Started](getting-started.md) | Prerequisites, clone, the lanes CI runs, run commands. |
| [Platforms](platforms.md) | Container, Windows, Raspberry Pi and Web builds. |
| [Camera Streaming](camera-streaming.md) | The installable ObservANT (packages, endpoints, arrival picture and video, [Home Assistant](camera-streaming.md#home-assistant) notifications and statistics, its tests), the Rust webcam inference, the GStreamer WebRTC pipelines. |
| [ESP32-S3 Companion & Camera](esp32.md) | The two firmware variants (Rust companion; ESP32-S3-EYE camera + ESP-DL), the shared USB-serial protocol (`Detection` and `CameraDetection`), the desktop-only Rust bridge, the Device page, the hardware probe, the on-device cat detection. |
| [Testing](testing.md) | What each kind of test proves (unit, property, fuzz, integration, end-to-end, performance), what the app's Dart suite checks, the rules that keep a green run honest, how to run them, the known gaps. |
| [Readmes](readmes.md) | Links to the key README files in this repository. |
| [Third-party Components](third-party-components.md) | Every open-source component the packages ship, with its license and source; generated. |
| [Project Operations](project-operations.md) | Tests, contribution process, repository hygiene, upgrade notes. |
| [Upgrade Guide](upgrade-guide.md) | Dependency and bridge updates. |

Update the docs in the same pull request as a change to behaviour or setup.
