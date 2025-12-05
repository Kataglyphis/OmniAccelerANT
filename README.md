# Kataglyphis-Inference-Engine

An inference engine with Flutter/Dart frontend and Rust/C++ backend, showcasing Gstreamer capabilities enhancd with AI. Read further if you are interested in cross platform AI inference.

[![Build + run + test on Linux natively](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart_on_native_linux.yml/badge.svg)](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart_on_native_linux.yml) [![Windows CMake (clang-cl) natively](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart_on_native_windows.yml/badge.svg)](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart_on_native_windows.yml) [![Build + run + test for web](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart_on_web_linux.yml/badge.svg)](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart_on_web_linux.yml)  
[![Automatic Dependency Submission](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dependency-graph/auto-submission/badge.svg)](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dependency-graph/auto-submission)
[![CodeQL](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/github-code-scanning/codeql)  
[![Dependabot Updates](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dependabot/dependabot-updates/badge.svg)](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dependabot/dependabot-updates)
[![TopLang](https://img.shields.io/github/languages/top/Kataglyphis/Kataglyphis-Inference-Engine)]()
[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.com/donate/?hosted_button_id=BX9AVVES2P9LN)
[![Twitter](https://img.shields.io/twitter/follow/Cataglyphis_?style=social)](https://twitter.com/Cataglyphis_)
[![YouTube](https://img.shields.io/youtube/channel/subscribers/UC3LZiH4sZzzaVBCUV8knYeg?style=social)](https://www.youtube.com/channel/UC3LZiH4sZzzaVBCUV8knYeg)

[**Official homepage**](https://kataglyphisinferenceengine.jonasheinle.de)

## Overview

Kataglyphis-Inference-Engine bundles a Flutter/Dart frontend, a Rust/C++ inference core, and a rich set of camera streaming pipelines powered by GStreamer. The repository acts as an end-to-end reference for building cross-platform inference products that target desktop, web, and embedded devices.

## Highlights & Key Features – Kataglyphis-Inference-Engine

### 🌟 Highlights

- 🎨 **GStreamer native GTK integration** – Leveraging users to write beautiful Linux AI inference apps.
- 📹 **GStreamer WebRTC livestreaming** with ready-to-use pipelines for USB, Raspberry Pi, and Orange Pi cameras.
- 🌉 **flutter_rust_bridge integration** – Ensures a seamless API boundary between Dart UI and Rust logic.
- 🐳 **Containerized development flow** plus native instructions for Windows, Linux, web.
- 🐍 **Python inference demos** for rapid experimentation alongside the Rust core.

### 📊 Feature Status

| Category | Feature | Status |
|----------|---------|--------|
| **Camera Streaming** | 📹 GStreamer WebRTC Livestream | ✔️ |
| **Supported Cameras** | 🔌 USB Devices | ✔️ |
| | 🍓 Raspberry Pi Camera | ✔️ |
| | 🟠 Orange Pi Camera | ✔️ |
| **Infrastructure** | 🐳 Dockerfile & Docker Compose | ✔️ |
| | 🎨 GTK Native Integration (Linux) | ✔️ |
| | 🌉 flutter_rust_bridge Bridge | ✔️ |
| **Testing** | 🧪 Advanced unit testing | 🔶 |
| | ⚡ Advanced performance testing | 🔶 |
| | 🔍 Advanced fuzz testing | 🔶 |
| **Frontend** | 🦋 Flutter Web Support | ✔️ |
| | 💻 Flutter Desktop (Linux) | ✔️ |

**Legend:**
- ✔️ Completed
- 🔶 In progress
- ❌ Not started

## Quick Start

1. Clone the repository with submodules:
   ```bash
   git clone --recurse-submodules git@github.com:Kataglyphis/Kataglyphis-Inference-Engine.git
   cd Kataglyphis-Inference-Engine
   ```
2. Initialize submodules if needed:
   ```bash
   git submodule update --init --recursive
   ```

Refer to the detailed docs below for platform-specific requirements, camera streaming pipelines, and deployment workflows.


## Documentation

| Topic | Location | Description |
|-------|----------|-------------|
| Getting Started | [docs/source/getting-started.md](docs/source/getting-started.md) | Environment prerequisites, installation, and run commands. |
| Platform Guides | [docs/source/platforms.md](docs/source/platforms.md) | Container, Windows, Raspberry Pi, and web build instructions. |
| Camera Streaming | [docs/source/camera-streaming.md](docs/source/camera-streaming.md) | GStreamer WebRTC pipelines and Python inference demos. |
| Upgrade guide | [docs/source/upgrade-guide.md](docs/source/upgrade-guide.md) | How to keep things up-to-date. |

Build the full Sphinx documentation from the `docs/` directory when you need a browsable site.

## Tests

Testing infrastructure is under active development. Track progress on the roadmap or contribute test plans via pull requests.

## Roadmap

Upcoming features and improvements will be documented in this repository.  
Please have a look [docs/source/roadmap.md] for more deetails.

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

### Protocols
- [WebRTC](https://webrtc.org/?hl=de)

### Tooling
- [tmux](https://github.com/tmux/tmux/wiki)
- [zellij](https://zellij.dev/)

## Contact

**Jonas Heinle**  
Twitter: [@Cataglyphis_](https://twitter.com/Cataglyphis_)  
Email: cataglyphis@jonasheinle.de

**Project Links:**
- GitHub: [Kataglyphis-Inference-Engine](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine)
- Homepage: [Official Site](https://kataglyphisinferenceengine.jonasheinle.de)