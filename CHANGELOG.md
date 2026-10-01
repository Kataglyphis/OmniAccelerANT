# Changelog

Versions follow `version:` in `pubspec.yaml`; `msix_config.msix_version` carries
the same three numbers with a fourth field of 0 (AGENTS.md § 4).

## 2.0.0+2 — 2026-10-01

A major release over `1.1.0+1` (2026-03-09): installs of 1.x do not upgrade in
place, so the major number moves. No tag is cut with this entry.

### Breaking

- **The app is OmniAccelerANT** (2026-09-05). The package and executable are
  `omni_accelerant` (was `kataglyphis_inference_engine`), the Linux packages
  `omni-accelerant`, the Linux application id `org.kataglyphis.omniaccelerant`,
  the Android application id `org.kataglyphis.omniaccelerant`, and the MSIX
  identity `Kataglyphis.OmniAccelerANT` (was
  `Kataglyphis.KataglyphisInferenceEngine`). A 1.x install stays beside a 2.x
  one until it is removed. The web build keeps its IndexedDB name, so a
  browser's data survives.

### Added

- Rust-owned webcam inference on the Stream page — Windows first, Linux since
  2026-09-16 — with frames pushed through the plugin's `knt_push_frame` C ABI.
- A Windows arm64 app, cross-built natives plus a native Flutter build on
  `windows-11-arm`.
- The live cat-detection WebRTC stream on the web build, served by
  `scripts/linux/cat-stream/serve.sh`, with producers on a Pi 5, a Pi Zero 2 W
  and a RISC-V board.
- Relocatable Linux packages (tar, deb, AppImage, flatpak) that carry their
  GStreamer and ONNX Runtime closure and the detector model; the flatpak has
  camera access (`--device=all`).
- Only the image's chain-built ONNX Runtime ships, proved by ANTfrastructure's
  G6 census on every lane.
- Every test runs on every lane that can host it:
  AGENTS.md § *What each lane tests*.
