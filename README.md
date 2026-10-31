<div align="center">
  <a href="https://jonasheinle.de">
    <img src="https://raw.githubusercontent.com/Kataglyphis/OmniAccelerANT/develop/images/logo.svg" alt="OmniAccelerANT logo: a sprinting ant and a lightning bolt" width="200" />
  </a>

  <h1>OmniAccelerANT</h1>

  <h4>An inference engine with a Flutter/Dart frontend and a Rust/C++ backend, showcasing GStreamer capabilities enhanced with AI.</h4>
</div>

[![Linux x64 · build + test](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/linux-x64.yml/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/linux-x64.yml)
[![Linux arm64 · build + test](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/linux-arm64.yml/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/linux-arm64.yml)
[![Windows x64 · build + test](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/windows-x64.yml/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/windows-x64.yml)
[![Windows arm64 · cross build + test](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/windows-arm64.yml/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/windows-arm64.yml)
[![Web · build + test](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/web.yml/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/web.yml)
[![Android · build + test](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/android.yml/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/android.yml)
[![Automatic Dependency Submission](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/dependency-graph/auto-submission/badge.svg)](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/dependency-graph/auto-submission)
[![TopLang](https://img.shields.io/github/languages/top/Kataglyphis/OmniAccelerANT)]()
[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.com/donate/?hosted_button_id=BX9AVVES2P9LN)
[![Twitter](https://img.shields.io/twitter/follow/Cataglyphis_?style=social)](https://twitter.com/Cataglyphis_)
[![YouTube](https://img.shields.io/youtube/channel/subscribers/UC3LZiH4sZzzaVBCUV8knYeg?style=social)](https://www.youtube.com/channel/UC3LZiH4sZzzaVBCUV8knYeg)

[**Official homepage**](https://kataglyphisinferenceengine.jonasheinle.de)

A Flutter/Dart app on a Rust/C++ inference core with GStreamer camera pipelines, for Windows,
Linux, Android and the web: an end-to-end reference for cross-platform inference on desktop, web
and embedded devices. ObservANT is the same stack as an installable camera that spots cats.

Dependency updates: run `bash scripts/linux/renovate-local.sh` to report, `--apply --dry-run` to plan,
and `--apply` to update. A real apply initializes a missing pinned hub and follows direct
submodules' remote default branches. CI checks the wrapper and config; see
[the shared Renovate guide](https://github.com/Kataglyphis/ANTfrastructure/blob/develop/docs/dependency-updates.md).
Both platforms use ANTfrastructure's locked uv project for CMake formatting.

Android CI checks launcher resources before building and verifies the project's MIT text in
the APK. The Linux package, MSI and MSIX builders check that text in their completed packages; see
[project operations](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/project-operations.md#package-license-and-launcher-checks).
Linux and Windows packages also carry the ONNX Runtime license and notices from their matching image wheel.
Every package ships the [third-party component list](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/third-party-components.md) with its license texts.

## Highlights

- **An installable ObservANT**: a `.deb`, AppImage, flatpak or Windows MSI that streams a camera to any browser and spots cats. The Flatpak packager verifies the committed app and nonempty bundle.
- **A small-board ObservANT bundle** whose producer build reuses [OxidANT's container helper](https://github.com/Kataglyphis/OxidANT/blob/develop/scripts/linux/observant/lib/producer-container.sh).
- **GStreamer WebRTC livestreaming** with ready-to-use pipelines for USB and Raspberry Pi cameras.
- **GStreamer native GTK integration**, for writing Linux AI inference apps.
- **ESP32-S3-EYE on-device cat detection**, its USB protocol in Rust, shown on the app's Device page.
- **AI Playground:** chat with a language model through any OpenAI-compatible endpoint, or locally on the chain GenAI on Linux and Windows.
- **flutter_rust_bridge** as the API boundary between the Dart UI and the Rust core.
- **Retained device sessions:** language, theme and layout changes preserve routed page state.
- **Containerized builds** in [ANTfrastructure](https://github.com/Kataglyphis/ANTfrastructure)'s images: a local run invokes the script CI invokes; all five Linux entry points and the two bundle checks reuse its CLI value parser.

## GPU package candidates

The on-demand [Linux](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/linux-gpu-candidates.yml)
and [Windows](https://github.com/Kataglyphis/OmniAccelerANT/actions/workflows/windows-gpu-candidates.yml)
workflows target NVIDIA x64/arm64 and AMD x64 on Linux, and NVIDIA/AMD x64 on Windows.
Open a successful run and download the matching vendor and architecture from its **Artifacts**
section (sign-in required). These candidates are unverified and separate from releases; the
current dependency pins block the workflows, and the hosted checks do not prove GPU inference.
See [project operations](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/project-operations.md) for formats and remaining checks,
and [camera streaming](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/camera-streaming.md) for host runtime requirements. CPU
packages remain available through the existing lanes.

## Quick start

```bash
git clone --recurse-submodules --branch develop https://github.com/Kataglyphis/OmniAccelerANT.git
cd OmniAccelerANT
pwsh -File scripts/windows/Invoke-LinuxLane.ps1   # the native Linux lane, in the family image
```

It needs `pwsh` 7 and `nerdctl` (Rancher Desktop on Windows). The other lanes, the Windows
build and the host prerequisites: [Getting Started](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/getting-started.md). Only want
ObservANT? A release's package installs it:
[a new camera in five steps](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/camera-streaming.md#installing-it).

## Documentation

| Topic | Read |
| --- | --- |
| What it is, its feature status per platform, literature | [docs/source/overview.md](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/overview.md) |
| Prerequisites, the lanes, the API docs | [docs/source/getting-started.md](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/getting-started.md) |
| Container source selection, Windows and ARM64 bundle checks, Android, Raspberry Pi and web builds | [docs/source/platforms.md](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/platforms.md#tar-pipe-inbound-exclusions) |
| ObservANT, the Rust webcam path and the WebRTC pipelines | [docs/source/camera-streaming.md](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/camera-streaming.md) |
| The AI Playground: language models, endpoints, the local GenAI | [docs/source/ai-playground.md](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/ai-playground.md) |
| ESP32-S3 companion, camera and shared host toolchain | [docs/source/esp32.md](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/esp32.md) |
| What each test proves, including shared Windows PE fixtures | [docs/source/testing.md](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/testing.md) |
| Gates, releases, local lanes, dependency upgrades | [docs/source/project-operations.md](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/project-operations.md) |
| CI quality reports, Ruff/ty, PowerShell syntax checks and refactor previews | [Shared quality tooling](https://github.com/Kataglyphis/ANTfrastructure/blob/develop/docs/code-quality-tooling.md) |
| Dependency and bridge updates | [docs/source/upgrade-guide.md](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/upgrade-guide.md) |
| The other READMEs in the tree | [docs/source/readmes.md](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/docs/source/readmes.md) |
| Rules for agents and contributors | [AGENTS.md](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/AGENTS.md) |
| Known work | [BACKLOG.md](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/BACKLOG.md) |
| Changes | [CHANGELOG.md](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/CHANGELOG.md) |

## Contributing and contact

OmniAccelerANT is one of the [Kataglyphis repositories](https://github.com/Kataglyphis/ANTfrastructure/blob/develop/docs/repository-family.md),
which share one way to contribute and one contact. Licence: MIT, see [LICENSE](https://github.com/Kataglyphis/OmniAccelerANT/blob/develop/LICENSE).
