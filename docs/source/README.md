<h1 align="center">
  OmniAccelerANT Docs
</h1>

<p align="center">
  Structured documentation for the Kataglyphis inference stack across Flutter, Rust/C++, and GStreamer.
</p>

<p align="center">
  <a href="overview.md">Overview</a> •
  <a href="getting-started.md">Getting Started</a> •
  <a href="platforms.md">Platforms</a> •
  <a href="camera-streaming.md">Camera Streaming</a> •
  <a href="esp32.md">ESP32-S3 Companion &amp; Camera</a> •
  <a href="testing.md">Testing</a> •
  <a href="readmes.md">Readmes</a> •
  <a href="project-operations.md">Project Operations</a> •
  <a href="upgrade-guide.md">Upgrade Guide</a>
</p>

---

## Documentation Map

| Topic | Description |
|-------|-------------|
| [Overview](overview.md) | High-level summary, ObservANT, targets, the repository's structure and design goals, the feature status per platform, and literature. |
| [Getting Started](getting-started.md) | Environment prerequisites, installation steps, the lanes CI runs, and run commands. |
| [Platforms](platforms.md) | Container, Windows, Raspberry Pi, and Web build guides. |
| [Camera Streaming](camera-streaming.md) | The installable ObservANT (packages, endpoints, arrival picture and video, [Home Assistant](camera-streaming.md#home-assistant) notifications and statistics, its tests), the Rust webcam inference, and the GStreamer WebRTC pipelines. |
| [ESP32-S3 Companion & Camera](esp32.md) | The two firmware variants (Rust companion and ESP32-S3-EYE camera + ESP-DL), the shared USB-serial protocol (`Detection` and `CameraDetection`), the desktop-only Rust bridge, the Device page, the hardware probe and the on-device cat detection. |
| [Testing](testing.md) | What each kind of test proves (unit, property, fuzz, integration, end-to-end, performance), what the app's Dart suite checks, the rules that keep a green run honest, how to run them, and the known gaps. |
| [Readmes](readmes.md) | Curated links to the key README files in this repository. |
| [Project Operations](project-operations.md) | Tests, contribution process, repository hygiene, and upgrade notes. |
| [Upgrade Guide](upgrade-guide.md) | Dependency and bridge update procedures. |

Use the navigation above to jump directly to the section you need. Keep documentation updates in the same pull request as code changes when behavior or setup instructions change.
