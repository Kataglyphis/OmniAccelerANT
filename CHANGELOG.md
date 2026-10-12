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
  when one last was, how many visits it counted, and when the latest 20 began and how
  long they lasted. `/snapshot.jpg` is the latest
  boxed frame and `/arrival.jpg` the frame each arrival was confirmed on. A cat counts
  after two detections in a row. Visits and the arrival frame outlive a restart.
- **It can notify** (2026-10-12): `notify_url` gets every arrival and departure as a
  JSON POST, which a Home Assistant webhook trigger takes as it is.
- **The Stream page shows the cat** (2026-10-12). Under the video: the cat cam's name,
  then "Cat in view", "Cat last seen: 14:32" or "No cat seen yet" in English or German,
  the latest visits with their stays, and the last arrival's picture. On a phone the video keeps its 4:3 and the line wraps.
- The web app boots without its Rust core, as Firefox and Safari need without
  cross-origin isolation; `serve.sh --http` serves the page with no certificate
  (2026-10-05).
- The integration test runs on Windows x64 and arm64, through `flutter drive` against
  the clang-cl app (2026-10-04/05).

### Fixed

- **The footer shows all seven social icons** (2026-10-12). Icon tree shaking had kept
  GitHub's alone, because ANThology held the others in a map that was not `const`.
- **The loading screen and cookie notice fit a phone** (2026-10-12). The page had no
  viewport tag, so a phone laid both out 980 px wide, like a desktop, until Flutter
  started. The cookie notice now stacks its text above a full-width button there.
- **The About page's skills fit a phone**, a title above each list instead of words
  broken mid-word, and the footer's copyright runs to the current year (2026-10-12).
- **The video box speaks the page's language** (2026-10-12): its status lines were
  English on the German page.
- **The desktop footer shows all its page links** (2026-10-12). Held at 150 px, it cut
  off the fourth row; it now takes its content's height. A new test lays the whole app
  out at phone, tablet and desktop size with the real font, and caught it.
- **The camera stream survives a language or theme change** (2026-10-12). Either left
  the video box at "Connecting to the signalling server", because the remounted view
  waited for connection events that had fired long before. The stream now lives in one
  controller per page load: a remount keeps the playing session, and a view that
  comes back later opens one at once.

### Changed

- **The cat cam needs a fraction of the CPU** (2026-10-11/12, measured on a Pi 5).
  - ONNX Runtime runs on two threads that sleep between runs, not four that spin: 131 %
    to 70 % of a core on the live camera.
  - While nothing moves, the model runs every 5 s, and not at all on a black picture: a
    still, empty scene went from 74 % to 12 % of a core, a dark room at night to 2 %.
  - Frames stay I420 from the camera to the encoder.
  - The web build goes out gzipped, and a revalidation answers 304 without reading a file.
- **The cat cam's web build ships zopfli-compressed** (2026-10-12): a first visit is
  3.75 MB, 180 kB less, and the board compresses nothing at run time. The packages leave
  out two Flutter renderers this build never loads, and the debug maps.
- **The service runs sandboxed** (2026-10-12): `systemd-analyze security` rates the unit
  1.8, down from 8.7, and the package test holds it at 2.5 or less.
- **The web build's first load is 2.8 MB lighter** (2026-10-12). Flutter web fetches
  every font its manifest declares before the first frame, and two of the three
  families were never rendered: this repo's Noto Sans (4 faces) and ANThology's
  Montserrat (18). The cat cam page's cold load went from 7.36 MB in 71 requests to
  4.55 MB in 49, and on a 10 Mbit/s link its first video frame from 7.7 s to 5.6 s.
  Pages render pixel for pixel as before. The checkout is 48 MiB lighter too.
- **The checkout is 6.6 MiB, down from 99 MiB** (2026-10-12). Every tracked file nothing
  referenced went: `dummy_assets/` (79.7 MiB), an unlisted video (12.3 MiB),
  `assets/images/barbell.png`, gstwebrtc-api's demo page and the UMD build only it
  loaded (both published with every web build), and ANThology's `Untitled.md`.
- **The app icons are 8-bit PNGs** (2026-10-12). They were stored at 16 bits per
  channel, which no browser shows: Chrome decodes old and new to the same pixels. The
  192 px icon Chrome fetches with every cold load is 26 kB instead of 123 kB, and the
  ten web and Android icons together 0.3 MB instead of 1.7 MB.

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
