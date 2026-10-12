# Changelog

Versions follow `version:` in `pubspec.yaml`; `msix_config.msix_version` carries
the same three numbers with a fourth field of 0 (AGENTS.md § 4).

## Unreleased

What landed on `develop` after 2.0.0+2. Most of it is the cat cam, whose guide is
`docs/source/camera-streaming.md` § *The cat cam package*.

### Added

- **An installable cat cam** (2026-10-05/06). The `cat_webrtc` producer, its GStreamer
  plugins, the chain ONNX Runtime, the model and the web build travel as one bundle:
  a .deb with a systemd service and a ufw profile, an AppImage that runs it or installs
  it as that service, and a flatpak. On Windows it is an MSI and a signed MSIX, each
  starting at logon with a firewall rule for the LAN. `web.yml` packages each one and
  install-tests it.
- **It reports the cat** (2026-10-11/12). `/healthz` says whether a cat is in view,
  when one last was, and how many visits it counted. `/snapshot.jpg` is the latest
  boxed frame and `/arrival.jpg` the frame each arrival was confirmed on. A cat counts
  after two detections in a row. Visits and the arrival frame outlive a restart.
- **It can notify** (2026-10-12): `notify_url` gets every arrival and departure as a
  JSON POST, which a Home Assistant webhook trigger takes as it is.
- **The Stream page shows the cat** (2026-10-12). Under the video: the cat cam's name,
  then "Cat in view", "Cat last seen: 14:32" or "No cat seen yet" in English or German.
  On a phone the video keeps its 4:3 and the line wraps.
- The web app boots without its Rust core, as Firefox and Safari need without
  cross-origin isolation; `serve.sh --http` serves the page with no certificate
  (2026-10-05).
- The integration test runs on Windows x64 and arm64, through `flutter drive` against
  the clang-cl app (2026-10-04/05).

### Changed

- **The cat cam needs a fraction of the CPU** (2026-10-11/12, measured on a Pi 5).
  - ONNX Runtime runs on two threads that sleep between runs, not four that spin: 131 %
    to 70 % of a core on the live camera.
  - While nothing moves, the model runs every 5 s, and not at all on a black picture: a
    still, empty scene went from 74 % to 12 % of a core, a dark room at night to 2 %.
  - Frames stay I420 from the camera to the encoder.
  - The web build goes out gzipped, and a revalidation answers 304 without reading a file.
- **The service runs sandboxed** (2026-10-12): `systemd-analyze security` rates the unit
  1.8, down from 8.7, and the package test holds it at 2.5 or less.

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
