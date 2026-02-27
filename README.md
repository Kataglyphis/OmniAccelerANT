<div align="center">
  <a href="https://jonasheinle.de">
    <img src="images/logo.png" alt="logo" width="200" />
  </a>

  <h1>Kataglyphis-Inference-Engine</h1>

  <h4>An inference engine with Flutter/Dart frontend and Rust/C++ backend, showcasing Gstreamer capabilities enhanced with AI. Read further if you are interested in cross platform AI inference. </h4>
</div>

[![Build + run + test on Linux natively](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart_on_native_linux.yml/badge.svg)](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart_on_native_linux.yml) [![Windows CMake (clang-cl) natively](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart_on_native_windows.yml/badge.svg)](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart_on_native_windows.yml) [![Build + test + run for web](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart_on_web_linux.yml/badge.svg)](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart_on_web_linux.yml)  
 [![Build + test + run android app](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart_build_android_app.yml/badge.svg)](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dart_build_android_app.yml)[![Automatic Dependency Submission](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dependency-graph/auto-submission/badge.svg)](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine/actions/workflows/dependency-graph/auto-submission)
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
- 🐳 **Containerized development flow** plus native instructions for Windows, Linux, web. For details in my build environment look into [Kataglyphis-ContainerHub](https://github.com/Kataglyphis/Kataglyphis-ContainerHub)
- 🐍 **Python inference demos** for rapid experimentation alongside the Rust core.

### 📊 Feature Status Matrix

#### Core Features

| Category | Feature | Win x64 | Linux x64 | Linux ARM64 | Linux RISC-V | Android |
|----------|---------|:-------:|:---------:|:-----------:|:------------:|:-------:|
| **Camera Streaming** | 📹 GStreamer WebRTC Livestream | ✔️ | ✔️ | ✔️ | ✔️ | N/A |
| **Supported Cameras** | 🔌 USB Devices | ✔️ | ✔️ | ✔️ | ✔️ | N/A |
| | 🍓 Raspberry Pi Camera | N/A | ✔️ | ✔️ | ✔️ | N/A |
| | 🟠 Orange Pi Camera | N/A | ❌ | ❌ | ❌ | N/A |
| | 📱 Native Camera API | N/A | N/A | N/A | N/A | ✔️ |

#### Infrastructure & Build

| Category | Feature | Win x64 | Linux x64 | Linux ARM64 | Linux RISC-V | Android |
|----------|---------|:-------:|:---------:|:-----------:|:------------:|:-------:|
| **Containerization** | 🐳 Dockerfile | ✔️ | ✔️ | ✔️ | ✔️ | N/A |
| | 🐳 Docker Compose | N/A | ✔️ | ✔️ | ✔️ | N/A |
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
| 🐧 **Linux** | x86-64 | ✔️ | Full GTK support, Docker ready |
| 🐧 **Linux** | ARM64 | ✔️ | SBC optimized (RPi, OPi support) |
| 🐧 **Linux** | RISC-V | ✔️ | Emerging architecture support |
| 🤖 **Android** | ARM64/x86-64 | ✔️ | Native camera, NDK integration |

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
   git clone --recurse-submodules --branch develop git@github.com:Kataglyphis/Kataglyphis-Inference-Engine.git
   cd Kataglyphis-Inference-Engine
   ```
2. Initialize submodules if needed.  
   If u used `--recurse-submodules` while cloning you are already good.  
   Otherwise you can use this :smile:
   ```bash
   git submodule update --init --recursive
   ```

Refer to the detailed docs below for platform-specific requirements, camera streaming pipelines, and deployment workflows.

```powershell
Im Projektroot ausführen: dart doc
Danach Static-Server installieren: dart pub global activate dhttpd
export PATH="$PATH":"$HOME/.pub-cache/bin"
Falls dhttpd nicht gefunden wird, einmal PATH ergänzen: $env:Path += ";$env:USERPROFILE\AppData\Local\Pub\Cache\bin"
Server starten: dhttpd --path doc/api --host 127.0.0.1 --port 8080
Im Browser öffnen: http://127.0.0.1:8080
```

## Documentation

| Topic | Location | Description |
|-------|----------|-------------|
| Getting Started | [docs/source/getting-started.md](docs/source/getting-started.md) | Environment prerequisites, installation, and run commands. |
| Platform Guides | [docs/source/platforms.md](docs/source/platforms.md) | Container, Windows, Raspberry Pi, and web build instructions. |
| Camera Streaming | [docs/source/camera-streaming.md](docs/source/camera-streaming.md) | GStreamer WebRTC pipelines and Python inference demos. |
| Upgrade guide | [docs/source/upgrade-guide.md](docs/source/upgrade-guide.md) | How to keep things up-to-date. |

Build the full documentation website with `dart doc`. The generated site in `doc/api` now includes the guides from `docs/source`.

## Tests

Testing infrastructure is under active development. Track progress on the roadmap or contribute test plans via pull requests.

## Roadmap

Upcoming features and improvements will be documented in this repository.  
Please have a look [docs/source/roadmap.md](docs/source/roadmap.md) for more deetails.

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
- GitHub: [Kataglyphis-Inference-Engine](https://github.com/Kataglyphis/Kataglyphis-Inference-Engine)
- Homepage: [Official Site](https://kataglyphisinferenceengine.jonasheinle.de)
