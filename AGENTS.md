# AGENTS.md

Guidance for coding agents (and new contributors) working in OmniAccelerANT.

**Reuse before adding Bash or PowerShell code.** Search this repository and every direct
submodule, including `third_party/ANTfrastructure`, for an existing implementation. Call or
extend its canonical owner, passing project-specific values as arguments. For new behavior
needed by multiple consumers, create or extend one shared owner module and call it here.
Keep unique product logic in this repository.

Laid out per ANTfrastructure's
[`shared/templates/AGENTS.md.template`](third_party/ANTfrastructure/shared/templates/README.md).
The rule that shapes it: *would this still be true in a different project?* If
yes, ANTfrastructure owns it and § 2 links to it. If no, it is written out in § 4.

## 1. What this project is

A Flutter/Dart app (`lib/`) for Windows, Linux, Android and web, over a Rust core and a C++
inference plugin.

| Path | What lives there |
| --- | --- |
| `lib/` | The Flutter/Dart frontend |
| `third_party/OxidANT` | Rust core, bridged via `flutter_rust_bridge`. `lib/src/rust/` is committed generated code — no build lane regenerates it; how to regenerate: § 4, *The frb Dart bindings* |
| `packages/kataglyphis_native_inference` | C++ inference plugin — **plain files, not a submodule**; a `pubspec.yaml` path dependency. Links AccelerANTgine (ONNX Runtime); GStreamer only on Android, from its SDK |
| `third_party/AccelerANTgine` | The inference core the plugin builds. Its own submodule, sibling to the plugin rather than nested inside it |
| `scripts/windows/`, `scripts/linux/` | Thin wrappers over ANTfrastructure drivers + this repo's own glue |
| `third_party/ANTfrastructure` | The submodule owning every reusable script, module and doc |
| `firmware/esp32-s3` | Rust firmware for the ESP32-S3 companion — its own crate, `esp` toolchain and `Cargo.lock`, never a workspace member |
| `firmware/esp32-s3-eye` | ESP32-S3-EYE camera firmware: ESP-IDF/ESP-WHO/ESP-DL (C/C++) plus the Rust USB protocol staticlib |
| `firmware/esp32-s3-probe` | One-boot hardware probe: PSRAM and the OV2640 SCCB scan (XCLK on GPIO15) |

**ESP32-S3 USB companion and camera (2026-10-18).** A board on its native USB port
(VID:PID `303a:1001`, `/dev/ttyACM0` / `COMx`) is a physical companion. Host side:
`crates/esp32-protocol` (shared `no_std` framing), `kataglyphis_esp32` (discovery +
reader/writer threads) and `src/api/esp32.rs` (frb). Board side: `firmware/esp32-s3`
(`esp-hal`, own toolchain), or the camera variant `firmware/esp32-s3-eye`, which runs the
ESP-DL cat model on the ESP32-S3-EYE and sends `CameraDetection` through a Rust `staticlib`.
The **Device** page is a view over `Esp32Controller` and shows the on-device count and best
score; the webcam engine forwards detections to the link on the inference thread, so the LED
reacts without a Dart round trip. The bridge is a desktop-only dependency built without
libudev (§ 4). Build/flash and the protocol: [`docs/source/esp32.md`](docs/source/esp32.md).
Tests: `cargo test -p kataglyphis_esp32_proto -p kataglyphis_esp32`, `flutter test
test/esp32_controller_test.dart`, and `cargo run -p kataglyphis_esp32 --example probe`
against a flashed board.

**Rust-owned webcam inference (Windows, and Linux since 2026-09-16).** The Stream page runs
webcam → ONNX → Flutter texture in Rust: `crates/media` GStreamer capture →
`src/webcam_engine.rs` → frb `src/api/webcam.rs` stream. Frames reach the texture through
the native plugin's `knt_push_frame` C ABI; only detection metadata crosses the bridge. **The
Rust core has no features and no opt-out** (owner, 2026-10-20): OxidANT gates by target alone
(`cfg(desktop)`, `wasm32`), so every Linux and Windows build carries the webcam engine, ORT
with tract as its fallback, and DirectML on Windows. Nothing here passes `--features`; never
add a feature variable or a Rust-less path back. `rust_builder/cargokit/` is vendored here,
**not** a submodule. `mfvideosrc` needs the `mediafoundation` GStreamer
plugin **and** a Windows client host; it falls back to `ksvideosrc`. Details in
[`docs/source/camera-streaming.md`](docs/source/camera-streaming.md)
§ *Rust-owned webcam inference*.

**Linux has this too as of 2026-09-16, and a frame has crossed it since 2026-10-05.** The
Linux plugin exports the `knt_push_frame`/`knt_api_version` C ABI, the build bundles the chain
ONNX Runtime, and the Stream page sends Linux and Windows to `RustWebcamView` by target. Since
2026-10-21 Linux has no C++ GStreamer MethodChannel fallback: the plugin there only creates
the texture Rust pushes into. Android and macOS, where the Rust webcam cannot run, keep the
plugin's MethodChannel pipeline. Never call `listCameras()` on the page's start: it starts
libcamera and held the first frame 0.94 s (2026-10-15). **This is an addition, not a
replacement**: the WebRTC cat detection stream below stays.

**A test-pattern frame travels Rust → `knt_push_frame` → texture on every native lane run**
(2026-10-05): `integration_test/webcam_frame_test.dart` starts `RustWebcamView` on
`videotestsrc` under Xvfb and polls the plugin's `hasPushedFrame`, the flag `knt_push_frame`
sets. A camera only changes the source, so none is needed; a real camera on Linux is still a
manual check. `scripts/linux/check-knt-abi.sh` dlopens the built plugin and checks the ABI's
symbols and error codes. Since 2026-10-01 the lane also starts the packaged bundle under Xvfb
and drives `integration_test/simple_test.dart` there (§ 5, *What each lane tests*). The
packaged artifacts carry their GStreamer/ONNX Runtime/model closure.

**Linux/web cat detection stream.** The same Stream page plays a WebRTC stream from
`third_party/OxidANT/crates/observant` (`kataglyphis_observant`): V4L2/libcamera → ONNX (cat
= COCO class 15) → boxes burned into the RGBA frames → `webrtcsink` with its own signalling
server. `scripts/linux/observant/serve.sh` puts HTTPS (or, with `--http`, plain HTTP) +
COOP/COEP + a `/webrtc-ws` proxy in front of it, so one build works on localhost, a LAN IP or
a Raspberry Pi. Per board (§ 2's glue list): a Pi 5 CSI camera's producer is **OxidANT's**
`third_party/OxidANT/scripts/linux/observant/run-producer-pi.sh`; a Pi Zero 2 W runs the
image with the same host-libcamera swap plus a `gst-launch` no-AI pipeline (the Rust
producer does not fit 512 MB); a RISC-V SoC runs the riscv64 variant natively with a USB
webcam (`--v4l2`). **The boards now run the installable ObservANT** (§ 2): producer, web
build and page together on `http://<board>:8080/`, under the package's systemd unit. Which
camera runs where, and on which version:
[`docs/source/camera-streaming.md` § *Where it runs*](docs/source/camera-streaming.md#where-it-runs);
a camera added or moved goes into that table. The container + `serve.sh` shape on
`https://<board>:8444/` is the manual one, which the Zero keeps; `serve.sh --producer-host`
only looks at one board from another host. Runbook:
[`docs/source/camera-streaming.md`](docs/source/camera-streaming.md) § *Cat detection stream (Rust, native)*.

**`observant` is this app's only WebRTC producer.** AccelerANTgine carries a second,
unrelated one — `Src/webrtc_streamer.{ixx,cpp}`, reached only through `cli_main.cpp`'s
`--webrtc` flag, with its own GStreamer signalling on `ws://127.0.0.1:8443`. It compiles into
the `AccelerANTgine` shared library that `packages/kataglyphis_native_inference` links, but
nothing in this app calls it: the plugin's sources never mention WebRTC, and the Stream
page's stream comes from the Rust crate. Do not wire the two together expecting a shared
signalling path.

## 2. What ANTfrastructure owns — links only

**Do not restate these procedures here.** Start at
[`third_party/ANTfrastructure/docs/INDEX.md`](third_party/ANTfrastructure/docs/INDEX.md),
which maps topic → owning document, so these links survive upstream reorganisation.

| Topic | Where |
| --- | --- |
| The winamd64 image — what it carries, its entrypoint, running it with `--isolation process` | `docs/windows-builds.md` |
| Stevedore setup and its post-install fixes | `docs/windows-host-setup.md` (Phase A), `docs/windows-stevedore-and-docker.md` |
| Windows containers idling at teardown: the patched runhcs shim and `TcpTimedWaitDelay` | `docs/windows-host-setup.md` § R1 and § C6, `third_party/ANTfrastructure/AGENTS.md` § *Stevedore Fixes After Install* |
| Isolation policy, and `docker commit` needing hyperv | `docs/windows-build-lanes.md` |
| An error message from either lane — symptom → cause → fix | `docs/failure-modes.md` |
| Bind mount vs tar-pipe, **Dev Drive filter setup**, container reuse, measured timings | `docs/windows-container-build-performance.md` |
| sccache across build hosts: the shared S3 level, its key and client setup, the bucket's server | `docs/windows-build-resources.md` § *Two cache levels*, `docs/windows-host-setup.md` § C7, `docs/build-cache-tiers.md` § *The shared S3 level*, `docs/linux-host-setup.md` § B9, `linux/sccache-s3/README.md` |
| sccache on a clang-cl C++20/23 modules build | `docs/windows-container-build-performance.md` § *sccache on a C++23 modules build* |
| The image's pkg-config and rustup provisioning | `docs/windows-builds.md` (§ *Toolchain pins and the provenance manifest*, § *Rust toolchain*) |
| Wiring this repo to ANTfrastructure — resolver, actions, libraries | `docs/adopting-in-a-new-project.md` |
| Linux container builds | `docs/linux-build-basics.md` |
| Running the Linux lane locally on Windows (Rancher Desktop/nerdctl), and **a bind mount that resolves but is empty** — containerd's mount namespace, Windows vs WSL path form | [`docs/rancher-desktop-linux-containers.md` § *An empty mount is not a missing drive*](third_party/ANTfrastructure/docs/rancher-desktop-linux-containers.md#an-empty-mount-is-not-a-missing-drive) |
| Why WSL 3's `wslc` does not replace Rancher Desktop yet | [`docs/rancher-desktop-linux-containers.md` § *WSL containers*](third_party/ANTfrastructure/docs/rancher-desktop-linux-containers.md#wsl-containers-wslc-are-not-a-replacement-yet) |
| The five shell-safety bug classes | `third_party/ANTfrastructure/AGENTS.md` § *Shell safety conventions* |
| **No ghost processes**: an agent's background job is a `systemd-run --user --unit=… -p RuntimeMaxSec=…` unit, never `setsid nohup … &`; test fixtures end on their own; the hub's runners kill whole process groups; `ghost-watch.sh` reports what slips through (2026-10-21: a 2.8-day spinner and 24 headless Chromes, 22 GB) | `third_party/ANTfrastructure/AGENTS.md` § *Background jobs and test processes (no ghosts)*, `docs/linux-host-setup.md` § B10 |
| Code comments: one line, only the why; API docs short; gated | `third_party/ANTfrastructure/AGENTS.md` § *Comments: one line, only the why* |
| Searching the tree: `rg`, not `grep -r` | `third_party/ANTfrastructure/AGENTS.md` § *Searching the tree: ripgrep (`rg`)* |
| appimagetool provisioning — pinned version + SHA256, not the moving `continuous` tag | `linux/scripts/02-toolchain/packaging-deps.sh`, subcommand `appimagetool` |
| Python venv + `uv` provisioning (installer downloaded to a file and SHA-checkable, never `curl \| sh`) | `linux/scripts/01-core/python_uv.sh` |
| The Dart gate for Linux lanes — deps, format, analyze, test, `--strict`/`--extra-package` | `linux/scripts/05-frameworks/flutter/flutter_checks.sh` |
| The CMake gate's machinery — `code_quality_find_cmake_files` + `CODE_QUALITY_CMAKE_EXCLUDE_PATHS` on Linux, `Initialize-UvVenvPython` on Windows | `linux/scripts/lib/code-quality.sh`, `windows/scripts/modules/WindowsUv.Common.psm1`, `WindowsFormatting.Common.psm1` |
| The canonical `.cmake-format.yaml` and locked formatter used on both platforms | `shared/config/README.md` and `quality/cmake-format/uv.lock` |
| Image and tag naming: `:latest`, `:winamd64`, variants, per-arch wrappers | `third_party/ANTfrastructure/AGENTS.md` § *Image and tag naming* |
| Branches, CI rounds (`[ci <lane>]`) and releases | [`docs/branch-and-release-strategy.md`](third_party/ANTfrastructure/docs/branch-and-release-strategy.md) |
| Every checkout on its branch tip (`git-sync-branches.sh`) | `docs/adopting-in-a-new-project.md` § *Putting every checkout on its branch* |
| Dependency upgrades: Renovate as a local CLI | `docs/dependency-updates.md` |
| Docs sites: the reusable `build-docs.yml`, the built-site link gate and its allow file, the site's `.htaccess` | [`docs/docs-sites.md`](third_party/ANTfrastructure/docs/docs-sites.md) |

Two upstream facts repeated here only because they bite before you reach a doc:

- Every ANTfrastructure PowerShell module declares `#requires -Version 7.0`, so
  `Build-Windows.ps1` and `Start-Windows.ps1` do too — launch with `pwsh`, never
  `powershell`. Under 5.1 it fails as an opaque `Import-Module` error.
- Composite actions resolve at `@develop`, so an ANTfrastructure change a workflow
  depends on must be pushed **before** the consumer change.
- The Windows container driver passes root-only exclusions to the shared runner;
  never rebuild its inbound file list here or exclude a root name with a tar pattern.

**This repo's glue** (deliberately thin):

- `scripts/windows/Resolve-BuildModule.ps1` — what *finds* the submodule, so it cannot live
  upstream. `Import-BuildModule <Name>` checks ANTfrastructure first, then
  `scripts/windows/modules/`, which holds only project-specific modules:
  `WindowsPaths.Common` (this repo's Flutter `build/windows/x64/{runner,plugins}` layout),
  `WindowsOrtRunner.Common` (stamps the hub's G6 verdict on the chain ONNX Runtime the hub's
  `WindowsOrtPayload.Common` stages into that runner — § 4), `WindowsLaneGuard.Common` (one
  lane at a time per checkout — § 5), `WindowsLaneSccache.Common` (the host's sccache S3 key
  for a local Linux lane — § 5) and `WindowsFlutterAot.Common` (catches a stale AOT target
  that `assemble` calls up to date).
- `scripts/linux/lib/antfrastructure.sh` — the bash twin: `antfrastructure_source` and
  `antfrastructure_path`, resolved from `${BASH_SOURCE[0]}` so they work from any working
  directory.

  Both are body-mode copies of the hub's templates, declared in
  `.antfrastructure-shared.manifest` and checked by `sync-shared-config.sh --check`: re-copy
  them after an upstream change, never edit them here
  ([`shared/config/README.md`](third_party/ANTfrastructure/shared/config/README.md#the-template-trees-are-owners-too)).
  `scripts/linux/lib/renovate-git-mode.sh` is the bootstrap's required exact-copy companion;
  the same drift check covers it.
- `scripts/agentic-loop/` — the adopted planner/executor loop: config, both runner wrappers,
  prompt overlays. Engine `opencode` (**v2 only**), executor
  `opencode-go/deepseek-v4.1-flash`, Windows build/test driver
  `scripts/windows/Build-Windows-Container.ps1`. Both runners are body-mode copies too
  (`agentic-loop-sh`, `agentic-loop-ps1`): only their header is this repo's. Rules and commands: § 5.
- `scripts/linux/observant/serve.sh` — serves the web build over TLS (`--http`: plain HTTP,
  no certificate) with COOP/COEP for the Rust core and proxies `/webrtc-ws` to the cat
  producer. No container; it is the deployment half of the demo.
  `--producer-host`/`--producer-port` front a producer on another board, `--state-dir` keeps
  concurrent instances apart.
- `third_party/OxidANT/scripts/linux/observant/run-producer-pi.sh` — **not in this repo**: the
  Pi 5 CSI producer moved to OxidANT, which owns the `observant` crate (decision D12). Why it
  swaps in the host's libcamera: [`docs/source/camera-streaming.md`](docs/source/camera-streaming.md)
  § *Cat detection stream (Rust, native)*.
- `scripts/linux/observant/package-producer-bundle.sh` — the container-less aarch64 producer
  bundle for a board too small for the image (Pi Zero 2 W); same section. It
  sources OxidANT's `scripts/linux/observant/lib/producer-container.sh` for the
  shared binary probe and Cargo build, while retaining automatic build on a
  missing binary, `--platform` and its explicit Bash entrypoint.
- `scripts/linux/observant/package-observant.sh` + `package/` — the installable ObservANT
  (`.deb`, AppImage, flatpak; riscv64 `.deb` and tarball). `observant.toml` is not a conffile,
  on purpose: [`docs/source/camera-streaming.md`](docs/source/camera-streaming.md) § *The ObservANT package*.
- `scripts/windows/observant/` — the Windows ObservANT (MSI, zip, signed MSIX; x64 and arm64):
  [`docs/source/camera-streaming.md`](docs/source/camera-streaming.md) § *The Windows ObservANT*.

**Deliberately not reused.** Two upstream Windows pieces were evaluated and rejected:
`WindowsAppRunner.Common` (its executable probe would launch the wrong one of this tree's
four runner exes and ignore `-Configuration`) and `Invoke-CmakeConfigureAndBuild` (mandatory
`-Preset`, no `-S`, no `--target`, and it fuses configure and build while the
`Native Assets Directory Fix` step must run between them). Both would be regressions here, so
do not "fix" their absence. Full reasoning:
[`docs/source/platforms.md`](docs/source/platforms.md)
§ *Windows pieces deliberately not reused*.

## 3. Critical invariant: submodule pins

Builds are supported only against the **recorded submodule gitlinks** — the commits CI
builds green. There are four:
[`third_party/ANTfrastructure`](third_party/ANTfrastructure) (the hub, § 2),
[`third_party/OxidANT`](third_party/OxidANT) (the Rust core behind flutter_rust_bridge),
[`third_party/AccelerANTgine`](third_party/AccelerANTgine) (the inference core the Windows
and Linux plugin builds link) and [`third_party/ANThology`](third_party/ANThology) (the
shared Dart package). `git submodule update --checkout --recursive` restores them. If you
want a drifted checkout, move the gitlink **and** fix the fallout in the same change: a tree
that walked forward from its gitlink compiles something other than what is committed, and
`git submodule status` marks that only with a `+`.

The opposite move, for local work on the newest code, is the hub's `git-sync-branches.sh`
([`adopting-in-a-new-project.md` § *Putting every checkout on its branch*](third_party/ANTfrastructure/docs/adopting-in-a-new-project.md#putting-every-checkout-on-its-branch)).
Here FUZZTEST stays on a release, because AccelerANTgine declares `branch = release_<date>`
for it (move that line for a newer one), and nanobind's `ext/robin_map` is the one `+` no repo
of ours can record. Commit the other gitlinks innermost repo first, or the next `git submodule
update` puts them back: on 2026-10-07 one reset three submodules two minutes after they moved.

Drift is guarded by ANTfrastructure's shared Pester suite, run from
[`.github/workflows/submodule-pins.yml`](.github/workflows/submodule-pins.yml) after any pin
bump. It checks both directions: each checkout sits at the recorded commit, and the recorded
commit is reachable from that submodule's remote — a gitlink bumped to a commit that was
never pushed builds on the machine that made it and on no other.

**Submodule URLs are `https://github.com/Kataglyphis/<repo>.git`, all four**, never `git@`.
Why, and how to change one:
[`adopting-in-a-new-project.md` § *Submodule URLs are https*](third_party/ANTfrastructure/docs/adopting-in-a-new-project.md#submodule-urls-are-https-never-git).

**What nothing here asserts:** `AccelerANTgine` and `OxidANT` each carry a
`third_party/ANTfrastructure` pin of their own, free to differ from this repo's. Bumping the
hub here does not bump the hub those two build against; that happens in their own
repositories.

## 4. Pitfalls specific to this project

**The Flutter router and device sessions survive appearance changes.** ANThology keeps one
router and publishes current settings through `AppAttributesScope`; do not recreate the router
to change language, theme or breakpoints. That would dispose `RustWebcamView`, disconnect an
owned `Esp32Controller` and discard camera-form edits. Its shared `FileActions` also owns the
landing page's browser downloads and native open/save dialogs. `test/app_layout_test.dart`
registers the dev-only `anthology_test_support` contracts for both layout and actual control taps.

**The texture ABI is generated from OxidANT.** `third_party/OxidANT/abi/texture.json` owns the
version and signatures; `scripts/generate-texture-abi.py` there generates its public C header
and Rust module. Both desktop plugins include `kataglyphis_texture_abi.h` from that submodule.
Rust refuses an incompatible `knt_api_version` before pushing a frame; do not duplicate the
declarations here. Version 1's existing signatures are unchanged.

**The desktop `add` API is an integration demo.** The About page's `add(3, 4)` reaches
AccelerANTgine through the native plugin while live webcam inference stays in Rust. Keep the
API and link until an explicit compatibility change retires that demo; the measured artifact
sizes and decision are in [overview.md](docs/source/overview.md#desktop-c-integration).

Everything here is false or meaningless in another repo — that is why it is written out
rather than linked.

- **Five scripts print a fixed line range of their own header as `--help`.**
  `scripts/linux/observant/package-producer-bundle.sh` (`sed -n '2,22p'`),
  `scripts/linux/observant/package-observant.sh` (`sed -n '2,15p'`),
  `scripts/linux/esp32/build-firmware.sh` (`sed -n '2,12p'`),
  `scripts/linux/esp32/build-eye-demo.sh` (`sed -n '2,7p'`) and
  `scripts/agentic-loop/Run-AgenticLoop.sh` (`head -28 | tail -27`): edit the
  header and the range together. `comment-size.allow` freezes those headers.
- **Six image gaps this repo once worked around are fixed in the image (2026-09-05); never
  bring a workaround back.** A reappearing one is an image regression
  ([`docs/source/platforms.md`](docs/source/platforms.md) § *Image gaps and image-tag history*).
  What stays here is `setup_compiler_cache`, which points `RUSTC_WRAPPER` and the CMake
  launchers at the hub's guarded `sccache-launcher.sh`.
- **The Android GStreamer SDK is in the image, and the image announces it.** It sits at
  `/opt/android/gstreamer` as a flat prefix (`gst-android/ndk-build`, `include/`, `lib/`);
  the hub's `linux/Dockerfile.package` sets `ENV GSTREAMER_ROOT_ANDROID=/opt/android/gstreamer`
  (checked in the published `:latest` amd64 config, 2026-10-01). Without `GSTREAMER_ROOT_ANDROID`
  the native plugin's `CMakeLists.txt` stops the Android lane at configure time with
  `GSTREAMER_ROOT_ANDROID must be set`; the plugin accepts both the per-ABI and the flat
  layout, so the path alone is enough. While the image shipped the SDK without the variable,
  `export_android_gstreamer_env` probed and exported it here, until 2026-10-01 (a no-op in CI
  since run 36154744222). If the configure error comes back, the image lost its `ENV`: fix
  the image, do not bring the probe back.
- **Every Android SDK component is pinned to what the image ships**, in one place: the `extra`
  block of `android/build.gradle.kts` (compileSdk 37, build-tools 37.0.0, NDK 29.0.14206865, CMake
  4.1.2, and the APK's one ABI). `/opt/android-sdk` is read-only, so anything else stops Gradle
  with `The SDK directory is not writable`. Detail, and why the override sits above
  `evaluationDependsOn(":app")`: [`docs/source/platforms.md`](docs/source/platforms.md) § *Android SDK components pinned to the image*.
- **The image's clang selects its own GCC; nothing here injects `--gcc-toolchain` any
  more** (`:latest` since 2026-09-29, hub CON16:
  [`linux-cross-builds.md` § *Clang cross wrappers*](third_party/ANTfrastructure/docs/linux-cross-builds.md#clang-cross-wrappers)).
  `export_toolchain_env` only sets `CC=clang CXX=clang++` and **refuses** a clang that selects
  anything but `gcc_toolchain_resolve_prefix()`'s GCC, so an older image fails there instead of
  at the link. Pull the image; do not put the flag back. History:
  [`docs/source/platforms.md`](docs/source/platforms.md) § *Android and cross-toolchain constraints*.
- **Editing a lane script while its container runs makes the log lie.** bash sources
  `container-steps.sh` once at start, so the edit does not take effect, but the log then
  contradicts the file on disk and the next reader (you, ten minutes on) draws the wrong
  conclusion. This cost one run: the log said "falling back to bare clang" while the file
  already had the fix. Wait for the container to exit.
- **ObservANT's Flatpak requires a committed OSTree app ref and a nonempty copied bundle.**
  Use ANTfrastructure's verdict after `flatpak-builder`: its exit code alone can lie in either
  direction. The stubbed regression checks both cases and the empty artifact.
- **The flatpak gets `--device=all`, because flatpak has no `--device=video`**
  (owner, 2026-10-01). `scripts/linux/lib/packaging-common.sh` sets
  `KATAGLYPHIS_FLATPAK_FINISH_ARGS`, which the hub appends to its four finish-args, and
  `package-linux.sh` prints the built app's `[Context]` and fails when an appended argument is
  missing from it. An empty value drops it.
- **A packaged Linux artifact carries its whole runtime closure** (2026-10-17), by the hub's
  rules ([`linux-build-basics.md` § *Linux packages that run outside the image*](third_party/ANTfrastructure/docs/linux-build-basics.md#linux-packages-that-run-outside-the-image)):
  `omni_accelerant` is the launcher of `omni_accelerant.bin`, the GStreamer libraries and six
  plugins travel in `bundle/lib`, and ORT is the image's chain build, proven by the hub's G6
  census in `check-bundle-closure.sh`. `rust_builder` puts ORT in `bundle/lib` before the packer
  runs (`Kept (already in bundle/lib, not copied)`), so a copy list without ORT is not a
  missing ORT. Detail: [`docs/source/camera-streaming.md`](docs/source/camera-streaming.md) § *Relocatable Linux bundles*.
- **Linux bundle fixtures come from the hub.** The closure and GStreamer element tests source
  `synthetic-elf-fixture.sh` and `gst-inspect-fixture.sh`; preserve their DT_STRSZ and Name-field
  options when changing a test, and keep the helper import fatal.
- **Linux bundle check options reuse the hub parser.** `check-bundle-gst-elements.sh` and
  `check-knt-abi.sh` call `scripts/linux/lib/bundle-options.sh`, which delegates value flags to
  ANTfrastructure's `parse_cli_value_options`; keep each gate's accepted path flag, error code,
  help text and the shared build-mode verdict. The native lane runs
  `scripts/linux/tests/test-bundle-options.sh`, including a mutated option destination.
- **The Rust binaries name the chain ORT's directory, and G6 must read them as importers.**
  OxidANT's loader keeps `/opt/onnxruntime/onnxruntime/core/` as a string, so only a whole
  NUL-terminated `__FILE__` path is an ORT fingerprint. A census calling `liboxidant.so` or
  `oxidant.dll` `UNPROVEN` or `STALE` is a hub pin older than 502b9089: move the pin, never
  OxidANT. Detail: [`docs/source/camera-streaming.md`](docs/source/camera-streaming.md) § *Relocatable Linux bundles*.
- **Rust `i64` is `int` natively and `BigInt` on web, so only the web lane catches the
  mismatch.** flutter_rust_bridge maps it to `PlatformInt64`, a per-platform typedef, so app
  code passing a plain `int` compiles everywhere except web:
  `Error: The argument type 'int' can't be assigned to the parameter type
  'BigInt'` — from `rust_webcam_view.dart`, a widget for the native path (then Windows only,
  Windows and Linux now). Wrap the value in `PlatformInt64Util.from(...)`, the identity on
  native. It lives in `package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart`,
  not in the public `flutter_rust_bridge.dart`, and importing the generated binding does not
  bring it along: Dart does not re-export transitively.
- **The web lane builds the wasm core with the image's dated nightly and its `rust-src`**
  (`RUST_NIGHTLY_TOOLCHAIN` from the pinned hub's `versions.env`), never the floating `nightly`,
  which downloads a channel each run and dies on the image's read-only layer. Detail: [`docs/source/project-operations.md`](docs/source/project-operations.md)
  § *The web lane's nightly toolchain*.
- **The web lane installs `flutter_rust_bridge_codegen` only when the image has none.**
  `:latest` ships the binary at `FLUTTER_RUST_BRIDGE_VERSION`, which it also exports; the
  unconditional `cargo install` that used to sit here rebuilt 174 crates on every CI run and
  then failed the lane. The guard is `command -v` plus
  `cargo install --locked --version "${FLUTTER_RUST_BRIDGE_VERSION}"`, so a bare host gets the
  pin the image carries — never a floating latest, and never `--force`.
- **The built web app gets a real browser check.** `scripts/linux/check-web-browser.sh`
  delegates to the hub's Node/Chrome check; its idle ObservANT fixture answers signalling,
  snapshots and API requests without weakening error checks. Keep the static branch routes
  there current; configured blog routes are read from their settings. Fallback glyph fonts
  need both `web/flutter_bootstrap.js` and the hub's locked font fetcher. Commands and scope:
  [project-operations.md](docs/source/project-operations.md#the-web-lanes-canvaskit-source).
- **Renaming the Rust crate touches committed generated code.**
  `lib/src/rust/frb_generated.dart` hard-codes the artefact name in
  `kDefaultExternalLibraryLoaderConfig`: `stem` (`oxidant` → `oxidant.dll`,
  `liboxidant.so`, `pkg/oxidant.js`) and `ioDirectory`
  (`third_party/OxidANT/target/release/`). No lane regenerates that file, so a `[lib] name`
  change in `Cargo.toml` stays silent until the app fails to load its library at runtime.
  Windows repeats the name in `scripts/windows/Get-WindowsBuildConfig.ps1` (`RustDllName`,
  `RustPluginSubDir`). Change all three together.
- **Models are fetched, never tracked** (owner, 2026-10-14). The detector is DEIM-D-FINE-N
  (Apache-2.0), released by [ModelANT](https://github.com/Kataglyphis/ModelANT);
  `third_party/OxidANT/resources/models/models.lock` pins each file's URL and SHA-256, and
  `third_party/OxidANT/scripts/linux/fetch-models.sh` (`--dest DIR`; Windows:
  `scripts\windows\Get-Models.ps1`) is the only way in. A checkout has no model until it
  runs, so the Rust webcam view on a dev build fails to load one: the native lane runs it
  before the build, the bundle and package scripts call it themselves. A new model goes
  into ModelANT and only the lock moves here; the old AGPL files left the history on 2026-10-17.
  Detail: `docs/source/camera-streaming.md` § *The detection model*.
- **The app version is written twice, and both move together.** `version:` in
  `pubspec.yaml` stamps the `.deb`, AppImage and flatpak names;
  `msix_config.msix_version` is the MSIX's, with its fourth field held at 0 for
  the Store. `test/pinned_artefacts_test.dart` fails when they drift. 2.0.0+2
  (2026-10-01) is a major bump over the `1.1.0+1` tag: the 2026-09-05 rename
  changed the package name, the executable, the Linux application id and the MSIX
  identity (`Kataglyphis.KataglyphisInferenceEngine` → `Kataglyphis.OmniAccelerANT`),
  so a 1.x install does not upgrade in place. `CHANGELOG.md` holds the rest.
- **`omniIndexedDbName` in `lib/src/db/sqlite3_storage.dart` is deliberately NOT the
  package name.** It still reads `kataglyphis_inference_engine` after the 2026-09-05 rename to
  `omni_accelerant`, because it names the **IndexedDB database in the visitor's browser**,
  which backs the sqlite3 VFS. Changing it renames nothing: it opens a *different, empty*
  database and orphans whatever the visitor had, with no error and no migration path. A
  rename here is a data migration and needs a copy step first; leaving it costs nothing,
  since only the browser sees the string. `omniSqliteDatabasePath` (`/kataglyphis.db`) is the
  same kind of name. The loader that opens them is ANThology's `loadSqlite3` (since
  2026-10-21); `test/pinned_artefacts_test.dart` pins both values.
- **The Android lane builds an arm64-v8a APK against five load-bearing Gradle constraints**:
  built-in Kotlin with a declared KGP 2.4.21 (so CodeQL scans c, cpp and rust only; never lower
  the KGP for it), `android.newDsl=false`, Cargokit's Gradle 9 and API-37 patches (keep them
  when bumping the vendored copy), `arm64-v8a` pinned in the app's `defaultConfig.ndk` and the
  lane's `--target-platform` (`check-apk-abi.sh` fails on any other ABI), and `compileSdk` 37. Each
  one's error and history: [`docs/source/platforms.md`](docs/source/platforms.md) § *Android and cross-toolchain constraints*.
- **The Rust manifest path is counted from the resolved plugin dir on Linux and from the
  unresolved one on Windows; do not unify them.** `rust_builder/linux/CMakeLists.txt` takes
  `REALPATH` first, because the kernel resolves the plugin symlink before `..`; Windows
  normalizes `..` lexically. Proof: [`docs/source/platforms.md`](docs/source/platforms.md) § *The Rust manifest path*.
- **Never `dart format .` here**; format the tracked files,
  `git ls-files -- '*.dart' ':!:rust_builder/**'`, as both lanes do
  ([`code-quality-tooling.md` § *`dart format`: the tracked files, in the floor's style*](third_party/ANTfrastructure/docs/code-quality-tooling.md#dart-format-the-tracked-files-in-the-floors-style)).
  **The `environment: sdk:` floor picks the style**: moving it from 3.11.4 to 3.13.0
  (2026-10-11) reformatted ten tracked files, so 3e4a252 failed every lane's format gate
  (reverted in 7af04e4; 0ebcf43 landed it formatted). After a floor move, regenerate
  `lib/src/rust/` and `lib/l10n/` in the image rather than hand-format them.
- **A single-arch image tag looks exactly like broken code.** `:latest` (then
  `:latest-cross`) was an amd64-only tag until 2026-09-04, so the arm64 matrix row ran x86-64
  binaries (`rustc: 1: ELF: not found`) and nothing in this repo could work around it. The
  tag is a proper OCI index now. Two habits survive the hunt: the architectures stay
  independent (`fail-fast: false` while they were one matrix; since 2026-09-24 two workflows,
  `linux-x64.yml` and `linux-arm64.yml`, independent by construction), and a
  `Failed to pull` line in a log is usually GitHub **echoing the retry script's source**, not
  running it. Write-up: [`docs/source/platforms.md`](docs/source/platforms.md)
  § *Image gaps and image-tag history*.
- **ASAN works, but only against Microsoft's runtime** — LLVM's loads after
  ucrtbase and aborts `bad-free` on the COM startup allocations a Flutter app
  makes, which is why `Start-Windows.ps1` stages the MSVC DLL and why no `/MT`
  override may exist anywhere. The runtime choice, the linked thunk pair and the
  `ASAN_OPTIONS` are ANTfrastructure's:
  [`docs/windows-clang-cl-sanitizers.md`](third_party/ANTfrastructure/docs/windows-clang-cl-sanitizers.md).
- **The clangcl-Debug preset ships with ASAN ON** and builds + runs green (Dart VM up,
  camera live). Historic gotchas, all fixed: naive ASAN dragged `/MT` into Flutter's `/MD`
  objects (`lld-link` RuntimeLibrary mismatch), and `kataglyphis_libfuzzer.exe` hit an
  `annotate_string` mismatch vs `clang_rt.fuzzer`.
- **Each Windows preset installs into its own `runner\<preset>\`** (and `plugins\<preset>\`);
  `Start-Windows.ps1 -Configuration` must name the same preset, and
  `x64-ClangCL-Windows-Release` is only the fallback. `runner\Release` is the MSIX copy of the
  first preset built.
- **ONNX Runtime in a Windows runner is the image's chain build, staged by the build and proven
  by the hub's G6** (owner rule 2026-09-23); never copy an ORT into a runner by hand.
  `Start-Windows.ps1` refuses a runner whose ORT is missing, unstamped, changed or foreign, since
  Windows would otherwise load System32's Windows ML 1.17. Detail: [`docs/source/platforms.md`](docs/source/platforms.md) § *ONNX Runtime in
  the Windows runner*.
  The MSIX wiring test parses `Build-Windows.ps1` with ANTfrastructure's `Get-TestScriptAst`,
  so a syntax error fails before its G6 ordering assertion.
  Windows PE test samples use ANTfrastructure's `New-OrtTestPe` and `New-TestPeFile`; each
  negative case changes its source fingerprint, package bytes or PE signature.
- **On an unprovisioned host** (`STATUS_DLL_NOT_FOUND`, or a ~6 MB process that exits) the
  runner lacks the image's runtime DLLs: stage `C:\runtime\bin` and its GStreamer plugins. Since
  2026-10-17 AccelerANTgine.dll and the VC++ runtime sit beside the exe on x64 as on arm64 (the
  plugin's CMake installs them there); a runner with a `bin\` is from an older build. Symptom table: [`docs/source/platforms.md`](docs/source/platforms.md) § *Troubleshooting containerized Windows builds*.
- **Dart file ops fail on bind-mounted paths.** `copySync`/`renameSync` fail (plain writes
  and cmd `copy`/`ren` work), so junction `.dart_tool` and `build` from the mounted workspace
  to container-local dirs before building. The bind-mount setup itself is upstream's (§ 2).
- **The native plugin needs pkg-config** and the image's baked `PKG_CONFIG_PATH`
  (GStreamer/FFmpeg/OpenCV `.pc` files under `C:\runtime`). Whether the image ships a
  pkg-config binary is upstream's problem; needing it is ours.
- **Cargokit hard-requires rustup.** The `rust_builder` Flutter plugin builds its crate via
  Cargokit during CMake install, and Cargokit will not use a scoop-only Rust. Install rustup
  **with a default toolchain**; only toolchain-less rustup shims are harmful. The winamd64
  image provisions exactly that now (hub `docs/windows-builds.md` § *Rust toolchain*), so
  this bites only outside it.
- **Cargokit builds `liboxidant` with the toolchain rustup resolves for OxidANT, never a
  floating `stable`**: a local patch in `rust_builder/cargokit/build_tool/lib/src/`
  (`builder.dart`, `rustup.dart`), both halves kept when bumping the vendored copy.
  `check-rust-toolchain.sh` fails the native and Android lanes on any other `rustc version`
  stamp. Detail: [`docs/source/platforms.md`](docs/source/platforms.md) § *Cargokit's Rust toolchain*.
- **Desktop PathProvider needs no JVM.** Its Android package brings the optional `jni` FFI plugin
  into Flutter's Linux and Windows discovery too. Both desktop `CMakeLists.txt` files disable JNI
  package discovery before the generated plugin rules; otherwise a build-host JDK enables
  `libdartjni.so` or `dartjni.dll` with an unbundled JVM dependency. Android's JNI path is unaffected.
- **The Linux plugin builds AccelerANTgine without its test suites and its Debug sanitizers**
  (`BUILD_TESTING` and both `myproject_ENABLE_SANITIZER_*` OFF before `add_subdirectory`):
  without them the Debug integration build cannot link. Windows keeps its ASan Debug preset on
  purpose. Detail: [`docs/source/platforms.md`](docs/source/platforms.md) § *The Linux plugin's AccelerANTgine build*.
- **Vendored ANTLR** (pulled in unconditionally by newer FUZZTEST) needs
  `WITH_STATIC_CRT OFF`, `ANTLR_BUILD_CPP_TESTS OFF`, `ANTLR_BUILD_SHARED OFF`, `/FIchrono`,
  and `LICENSE.txt` staged at the build root — its install rule assumes a monorepo layout.
  Wired up in `third_party/AccelerANTgine/third_party/CMakeLists.txt`, the inference core's
  own dependency list, not the plugin's.
- **The Stream page needs no secure context.** Only the Rust wasm core wants cross-origin
  isolation, and on web `main()` treats a failed `RustLib.init()` as optional, so Firefox and
  Safari over plain HTTP still boot; only the About page's Rust demo goes dark. `serve.sh
  --http` serves that, and without `--http` it ends TLS on 8444 in front of the producer. Detail:
  [`docs/source/camera-streaming.md`](docs/source/camera-streaming.md) § *No secure context needed*.
- **`signalingServerUrl` may be host-relative, and only web resolves it.** A value starting
  with `/` (the committed `/webrtc-ws`) becomes `wss://<page-host>/webrtc-ws` in
  `WebRTCSettings.fromJsonFile` (`lib/settings/webrtc_settings.dart`); absolute `ws(s)://`
  URLs pass through untouched, as does everything on native, where the value is unused
  (`WebRTCView` is web-only).
- **A Pi Zero 2 W, or any VC4/unicam Pi, runs the image only with the host's libcamera
  stack**: the container, a hostlibs mount and `--entrypoint` (the image's `entrypoint.sh`
  overrides `LD_LIBRARY_PATH`); the Zero runs a `gst-launch` pipeline without the model.
  Bring-up and traps: [`docs/source/camera-streaming.md`](docs/source/camera-streaming.md) § *Cat detection stream (Rust, native)*.
- **A RISC-V board runs the same image natively**: a USB webcam needs `--v4l2`, a udev rule
  for the camera node's ACL and UFW rules, and `serve.sh --producer-host` takes the board's IP,
  never its mDNS name. Detail: [`docs/source/camera-streaming.md`](docs/source/camera-streaming.md) § *Cat detection stream (Rust, native)*.
- **Autostart is opt-in.** Boards on the ObservANT package use its systemd unit; the manual
  setups' `~/cat-cam.sh start` removes a stale container first, or the named run fails with
  `name-store error`.
- **The frb Dart bindings must match the Rust runtime's frb version.** They were stale at
  2.12.0 against 2.13.0 and the web build died with an empty `Uncaught` before
  `pkg/oxidant.js` loaded. Regenerate both sides together:
  `flutter_rust_bridge_codegen generate` writes `lib/src/rust/` **and** OxidANT's
  `src/frb_generated.rs`; when the wasm artefacts are involved,
  `flutter_rust_bridge_codegen build-web --release --rust-root
  third_party/OxidANT`. `web/pkg/` is generated and gitignored. The codegen is a cargo binary
  baked into the build image, NOT a pub dependency; on a bare host run
  `cargo install --locked --version <pin> flutter_rust_bridge_codegen` first, where `<pin>`
  is `FLUTTER_RUST_BRIDGE_VERSION` in the image or, off it, the `flutter_rust_bridge` version
  pinned in `third_party/OxidANT/Cargo.toml` (`=2.13.0` today) — a floating latest
  desynchronises the Dart bindings from the Rust runtime.
- **The ESP32-S3 bridge is desktop-only and its firmware is a separate toolchain.**
  `kataglyphis_esp32` sits in a `[target.'cfg(any(target_os = "linux", target_os =
  "windows", target_os = "macos"))'.dependencies]` block; moving it to `[dependencies]` drags
  `serialport` into Android and wasm. `build.rs` sets `cfg(desktop)` from
  `CARGO_CFG_TARGET_OS`, and `src/api/esp32.rs` has stubs for the other targets. `serialport`
  is built with `default-features = false`: its Linux `/sys/class/tty` fallback does the
  discovery, no libudev enters the packaged bundle, and the riscv64 cross lane is unaffected.
  The firmware is not a workspace member: it needs the `esp` toolchain,
  `xtensa-esp32s3-none-elf` and its own `Cargo.lock`; the protocol crate is the only shared
  Rust, so a protocol field change touches `crates/esp32-protocol`, `crates/esp32`,
  `src/api/esp32.rs` and `firmware/esp32-s3` together. Espup supports aarch64 Linux, but
  `/tmp` on the Pi is a 4 GB tmpfs: install under `$HOME/.cache`, or the rust-docs unpack dies
  with `No space left on device`. `scripts/linux/esp32/build-firmware.sh` flashes with
  `--before usb-reset` for the native USB port, `default-reset` for a UART bridge, and runs
  only the flash step as root (rootless nerdctl remaps the device to `nobody:nogroup`); its
  named volume and the rest: `docs/source/esp32.md` § *Build and flash the companion firmware*.
- **Share host espup setup.** `firmware/esp32-s3/flash.sh` and
  `scripts/linux/esp32/build-eye-demo.sh` source `scripts/linux/lib/espup-env.sh`; keep
  the preferred toolchain, fallback and failure status in that one helper.
- **The ESP32-S3-EYE's OV2640 does not answer SCCB until XCLK runs:** a scan without XCLK
  finds only the ES8311 codec at `0x12`, and a busy-loop clock also missed the sensor. Use
  **LEDC 10 MHz on GPIO15**, as `firmware/esp32-s3-probe` does. The board's pins, the camera
  firmware (variant A: ESP-IDF + `esp32-camera`/ESP-DL with a Rust protocol layer) and its
  build: `docs/source/esp32.md` § *Camera and on-device AI*. The rules that bite:
  - **The 8 MB flash is tight for ESP-DL**: a 320 px YOLO11n model plus ESP-IDF and the Rust
    app does not fit comfortably; target a 96–160 px model unless the board is replaced with
    a 16 MB variant.
  - `scripts/linux/esp32/build-eye-demo.sh` builds ESP-WHO's `object_detect` with
    `cat_detect` in `espressif/idf:release-v5.5`, a separate image from the family
    `:latest`, which has no ESP-IDF.
  - **The app console must be UART0** (`CONFIG_ESP_CONSOLE_UART_DEFAULT`); on the USB port it
    consumed the host's `HostHello` before the Rust read. The USB port carries the protocol,
    so `idf.py monitor` is not the view; use the host probe or the app.
  - **ESP-WHO `b6ac2be`, BSP `5.0.2` and `cat_detect` `0.3.0` move only together with the
    example code and sdkconfig defaults**: master's code uses the BSP 6.0.0
    `bsp_camera_cfg_t` API while its lock and defaults are still 5.0.2. The script also
    disables the example's BSP LED block (absent from 5.0.2) and patches the esp-dl 3.3.13
    API.
- **Windows host only: the webcam reaches WSL over usbipd, and WebRTC needs mirrored
  networking.** `usbipd attach --wsl --busid <id>` (bus ids change) plus `modprobe uvcvideo`
  gives the container `/dev/video0`; `[wsl2] networkingMode=mirrored` in
  `%USERPROFILE%\.wslconfig` makes UDP media work — NAT mode drops it, and the port mapping
  looks fine until the stream never arrives. Both vanish on a WSL restart. `nerdctl pull` of
  a Docker Hub image can also fail on credential lookup (`A specified logon
  session does not exist`); pulling from inside the VM with an empty `DOCKER_CONFIG` worked.

## 5. Build, run, test

**Both lanes run the same thing locally and in CI; reproduce locally first, CI is not a
debugger.** **Run one lane at a time**: every local lane bind-mounts the same checkout and its
per-host generated files (`android/local.properties`, `.dart_tool`, the plugin symlinks), so two
at once break each other with errors that name neither. CI never sees this.

The five Linux CI entry points parse value flags through `scripts/linux/lib/ci-options.sh` and
ANTfrastructure's `parse_cli_value_options`. Keep each lane's accepted options, defaults and
validation in that contract; `--no-package` belongs only to the native lane. Web and native
Linux reject `--run-codeql true` because neither implements a scan.

Windows builds run in the `:winamd64` container, and **CI runs the exact same
`Build-Windows.ps1`** through the hub's `run-in-windows-container`. Locally:

```powershell
& "$env:ProgramFiles\Stevedore\bin\docker.exe" run --rm --isolation process `
  --mount "type=bind,source=$PWD,target=C:\ws-mnt" -w C:\ws-mnt `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64 `
  pwsh -NoProfile -ExecutionPolicy Bypass -File C:\ws-mnt\scripts\windows\Build-Windows.ps1 `
    -SkipMsixPackaging
```

- **In the container with Stevedore's `docker.exe`**, never on the host (Rancher's shims come
  first on `PATH`, and the host's CMake is too old), and **never mounted at a path the image
  has**: that fails with `hcs::CreateComputeSystem` (images before 2026-09-26 held `C:\workspace`).
- **On the dev box, junction first**: start without the root and plugin `.dart_tool`/`build` and
  junction those four to container-local directories, or Dart's and CMake's write-then-rename
  steps fail on the mount. `Build-Windows-Container.ps1` streams the sources in and needs neither.
- **A failed step does not abort the run**, and the log still ends with `=== Build Complete ===`:
  trust the exit code and `failedSteps` in `logs/build-summary-*.json`, never the log tail.
- Presets `clangcl-{debug,profile,release}`, `msvc-{debug,release}`;
  switches `-SkipTests`, `-SkipFormat`, `-SkipDocs`, `-CleanBuild`, `-SkipMsixPackaging`,
  `-SkipBootstrapFlutterBuild`, `-ContinueOnError`/`-StopOnError`, `-CodeQL` (the closing
  Delivery Check cannot be skipped). Logs in `logs/`, API docs in `doc/api`.
- **MSIX packaging runs only locally**: CI passes `-SkipMsixPackaging`, and `runner\Release` is the
  flat copy of the first preset that msix reads.
- **Installer checks share the hub's assertions.** The app MSI/MSIX and both ObservANT checks
  call `WindowsSmokeTest.Common` and exit with its failed count; the app's PE architecture check
  reads the file and target facts through `WindowsTargetArch.Common`.
- **CI** ([`windows-x64.yml`](.github/workflows/windows-x64.yml)): the hub's PowerShell lint on the
  host before the ~54 GB image pull, the Release build with the lane's quality gates, four host
  checks of the runner (C ABI, plugin gtest, import walk, launch smoke with the ORT stamp), and
  `build-clang-debug`, which builds the ASan Debug app and its integration twin in one container
  (`Build-WindowsDebugApps.ps1`) for the launch smoke and `flutter drive`. The checkout prunes
  `third_party/DocumANTation` (`'$GIT_DIR' too big`), so every path is absolute under the
  short-path clone.
- **The Release job keeps sccache's cache across runs** (2026-10-17): `.ci-cache` through
  `actions/cache`, saved from `develop` and pruned to one entry, moved in and out by
  `Build-Windows.ps1` through the hub's `Restore-CiCompilerCache` and `Save-CiCompilerCache`.
  It is used only on an sccache that keys clang-cl's module importers right
  (mozilla/sccache#2876): the hub's build or 0.19.0 on (`-RequireModuleSafeSccache`). An image
  with 0.18.0 serves stale importer objects, so such a run neither uses nor saves it and says so.
- **Windows arm64** ([`windows-arm64.yml`](.github/workflows/windows-arm64.yml)) is a hybrid,
  since Flutter cannot cross-build `windows-arm64`: the natives cross-build in the hub's arm64
  container, the app builds on `windows-11-arm` with clang-cl through `Build-WindowsArm64App.ps1`
  (never a plain `flutter build windows`, which picks MSVC), and the device runs x64's tests.

All of it, with the measurements: [`docs/source/platforms.md`](docs/source/platforms.md) § *The Windows lanes in detail*.

**The agentic loop** (`scripts/agentic-loop/`, adopted 2026-09-13) runs opencode **v2 only**
(owner directive 2026-09-28), executor `opencode-go/deepseek-v4.1-flash` and planner
`opencode-go/glm-5.2`, builds through `Build-Windows-Container.ps1`, and auto-commits with `git
add -A`: check whether it is live before working in the same tree. Edit its overlays, never the
generated `.opencode/agents/`. Installing v2 and its flags: [`docs/source/platforms.md`](docs/source/platforms.md) § *The Windows lanes in detail*.

```powershell
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1            # planner + executor
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1 -DryRun    # wiring check
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1 -PlannerOnly
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1 -ExecutorOnly
```

### What each lane tests

Owner goal 2026-10-01: every test runs on every lane that can host it. A blank cell is a test
that cannot run there; why, lane by lane: [`docs/source/testing.md`](docs/source/testing.md)
§ *Why a lane cannot run a test*.

| Test | Linux x64 / arm64 | Windows x64 | Windows arm64 | Android | Web |
| --- | --- | --- | --- | --- | --- |
| App Dart tests (`test/`) | yes | yes, in the image | yes, arm64 Dart VM | yes | in Chrome |
| Plugin Dart tests (`packages/kataglyphis_native_inference/test/`) | yes | yes, in the image | yes, arm64 Dart VM | yes | in Chrome |
| Built app in Chrome, all routes, files and external hosts (`check-web-browser.sh`); its three planted-failure checks | | | | | yes |
| Plugin gtest (`kataglyphis_native_inference_test`) | yes | built in the image, run on the host | yes, on the device | | |
| Plugin C ABI (`knt_*`) | `check-knt-abi.sh` | `Test-KntAbi.ps1`, host | `Test-KntAbi.ps1`, device | | |
| G6 over the shipped tree | `check-bundle-closure.sh` | at build, again on the host | at the natives build, again on the device | | |
| Every pipeline element from the bundled plugins alone (`check-bundle-gst-elements.sh`) | yes | | | | |
| Bundle gate's mutation suite, the element gate's stub suite | yes | | | | |
| Dart coverage of `lib/` against a floor (the hub's `check-dart-coverage.sh`) | yes | | | | |
| Web artefacts: `<title>` vs manifest name, `sqlite3.wasm` vs its pin, 8-bit icons (the hub's `check-web-artefacts.py`) | yes | | | | |
| Plugin C++ format (`check-plugin-cpp-format.sh`) and its planted-deviation suite | yes | | | | |
| Import walk | (the closure gate) | host, `-Standalone` | device | | |
| Launch smoke, 20 s | under Xvfb, on the host's and the bundled glibc, and the app flatpak | host | device | | |
| Integration test (`integration_test/simple_test.dart`) | under Xvfb | `flutter drive` against the clang-cl app | `flutter drive` (the Debug app) | | |
| Webcam frame through `knt_push_frame` (`integration_test/webcam_frame_test.dart`) | under Xvfb, test pattern | | | | |
| Frame timings in profile mode (`integration_test/performance_test.dart`, `flutter drive --profile`), against the median of the last 20 default-branch runs (the hub's `frontend-perf-report` action) | x64, under Xvfb | | | | |
| Pester (`scripts/windows/tests`) | | `windows-2025` | `windows-11-arm` | | |
| Plugin JVM test | | | | yes | |
| APK ABI gate (`check-apk-abi.sh`) and its synthetic-APK suite | | | | yes | |
| `liboxidant`'s rustc stamp (`check-rust-toolchain.sh`) and its suite | yes | | | yes, in the APK | |
| APK on the emulator, 20 s (`check-apk-on-emulator.sh`) and its stub suite | | | | yes, API 35 x86_64 + ARM translation, on KVM | |
| ObservANT .deb, AppImage and flatpak install checks (`test-observant-package.sh`) | | | | | in `web.yml`'s `observant` jobs, x64 and arm64 |
| ObservANT MSI install checks (`Test-ObservANTWindows.ps1`) | | | | | x64 in `web.yml`'s `observant-windows` job, in `:winamd64`; arm64 on `windows-11-arm` after the hub's arch gate (`observant-windows-arm64-test`) |
| ObservANT MSIX package checks (`Test-ObservANTMsix.ps1`, without `-Install`) | | | | | in `web.yml`'s `observant-windows` jobs, in `:winamd64` and `:winarm64` |
| The app's MSI and MSIX: installed, started from Program Files and from the app entry without PATH help, removed (`Test-OmniAccelerANTInstallers.ps1`) | | host, after `Package-OmniAccelerANT.ps1` | device, the same | | |
| `.deb`, AppImage and tarball on a bare `ubuntu-26.04` runner, 20 s under Xvfb (the hub's `clean-host-package-check`) | yes | | | | |

**When the lanes run** is the family's rule (owner, 2026-10-15):
[`branch-and-release-strategy.md`](third_party/ANTfrastructure/docs/branch-and-release-strategy.md).
A push to `develop` runs Linux x64 alone; a change to Windows-, arm64-, Android- or web-only code
asks for its lane in its commit message (`[ci windows]`, `[ci arm64]`, `[ci android]`, `[ci web]`,
`[ci all]`). `main` moves only by the owner's fast-forward, and every push to it is a release.
This repo's release steps: project-operations.md § *Release Hygiene*.

### The Dart gate in 23 seconds, without a lane

The Windows dev box has no Flutter SDK, but the image has one: the Dart gate alone against a
bind-mounted checkout takes 23 s warm. `scripts/windows/Invoke-DartChecks.ps1` runs it
(`-SkipFormat`, `-SkipAnalyze`, `-SkipTest`, `-Fix`, `-Engine wslc`). It is not the lane (no
build, no CMake gate, no Rust or C++): iterate with it, believe the lane. The raw `nerdctl`
commands, the pub-cache volume's one-time chown and the measurements:
[`docs/source/project-operations.md`](docs/source/project-operations.md) § *The Dart gate without a lane*.

### The Linux lane, locally

`scripts/windows/Invoke-LinuxLane.ps1` runs a lane's own script in the same image with the
same arguments as its workflow; `-CheckParity` diffs those values against the workflow and
starts nothing, so change driver and workflow together. Its detail, every error message and
the CI invocation: [`docs/source/project-operations.md`](docs/source/project-operations.md)
§ *The Linux lanes, run locally*.

| `-Lane` | script | workflow |
| --- | --- | --- |
| `native` (default) | `ci-container-run-native-linux.sh` | [`linux-x64.yml`](.github/workflows/linux-x64.yml) / [`linux-arm64.yml`](.github/workflows/linux-arm64.yml), by `-Arch` — both run [`reusable-linux.yml`](.github/workflows/reusable-linux.yml) |
| `android` | `ci-container-run-android.sh` | [`android.yml`](.github/workflows/android.yml) |
| `web` | `ci-container-run-web-linux.sh` | [`web.yml`](.github/workflows/web.yml) |

```powershell
.\scripts\windows\Invoke-LinuxLane.ps1                                  # native, x64
.\scripts\windows\Invoke-LinuxLane.ps1 -Lane android
.\scripts\windows\Invoke-LinuxLane.ps1 -Lane web
.\scripts\windows\Invoke-LinuxLane.ps1 -Arch arm64                      # needs QEMU, see below
.\scripts\windows\Start-Windows.ps1 -Configuration x64-ClangCL-Windows-Release  # run a Windows build
```

- **One lane at a time** (above): a real run refuses while another lane's container or a
  Windows build is up (`-Force` overrides; `WindowsLaneGuard.Common`).
- **Everything write-heavy stays off the host mount.** A Windows bind mount refuses `utime`,
  `chmod` and `fchmod`, each with a different misleading error, so the build tree, pub's cache
  and cargo's target live on named volumes, the flatpak work under `/tmp/flatpak-work`;
  only finished artifacts go to `out/`.
- **sccache has two levels on a local lane** (2026-10-17): its own named volume on
  `/var/cache/sccache`, since every `flutter clean` empties `build/`, and the shared S3
  bucket. The host key (`Set-SccacheS3Level.ps1` on Windows, `set-sccache-s3-level.sh`
  on Linux) is bound at `/run/secrets/sccache_s3` (`WindowsLaneSccache.Common`), and the
  lane's exit waits for the uploads. With both local caches deleted, the native lane hit
  99.76 % from the bucket. `KATAGLYPHIS_SCCACHE_S3=off` drops the S3 level; CI never has it.
- **On a Linux host the driver runs a rootless engine's lane as root**, with
  `TAR_OPTIONS=--no-same-owner`
  ([`linux-build-basics.md`](third_party/ANTfrastructure/docs/linux-build-basics.md#a-lane-under-a-rootless-engine-on-a-linux-host-runs-as-root)).
- **Rancher's traps are the hub's**
  ([`rancher-desktop-linux-containers.md`](third_party/ANTfrastructure/docs/rancher-desktop-linux-containers.md)):
  `-v name:/path` is a bind, so the driver spells every volume `--mount type=volume,…`; an empty
  mount is `D:` missing from containerd's namespace or a WSL path; the android lane's emulator
  needs KVM loaded once per VM boot (or `-EmulatorSmoke false`); arm64 needs QEMU registered once
  per VM boot, and an emulated run makes tar and deb only.
- **A `pubspec.lock` older than a workspace member's `pubspec.yaml` reds the web lane**
  (`Failed to set file modification time`): touch the lock on the host and rerun.
- **Flutter comes from the image** (`/opt/flutter`); no lane installs or pins it. To change
  the version, change the image.
- **`--app-name` derives from `pubspec.yaml`** (`resolve_app_name`); never hard-code it.
- `KATAGLYPHIS_LINKER=lld|mold` is a local opt-in for the native lane; CI never sets it.

**CodeQL runs only when asked for, never in CI** (owner directive 2026-09-17): `-Lane android
-RunCodeQL` scans c, cpp and rust (not Java/Kotlin, § 4) and `Build-Windows.ps1 -CodeQL` the
Windows build; budget hours. Its scope and the Windows run:
[`docs/source/project-operations.md`](docs/source/project-operations.md) § *CodeQL, only on
request*.

**A pre-commit hook runs CI's first gates**: `git config core.hooksPath scripts/git-hooks`
once per clone. **Every lane's Dart gate is strict** (format on the tracked files, analyze,
test, the plugin's tests too), and `Invoke-LinuxLane.ps1` passes `-StrictChecks true` as CI
does. The CMake format gate (13 hand-maintained files) and the plugin's C++ format gate (15
files) are fatal; never widen either onto generated or vendored trees. Detail:
[`docs/source/project-operations.md`](docs/source/project-operations.md) § *Gate strictness
and the pre-commit hook*, § *The CMake format gate*, § *The plugin's C++ format gate*.

### Dependency upgrades

**Submodule and package upgrades go through Renovate as a local CLI, never by hand, and a run
only reports** (owner directive 2026-09-11): `-Apply` only when the owner asked for it in that
turn. CI verifies the wrapper and config without applying upgrades. On this host, in the family Linux image:

A real `-Apply` initializes a missing pinned hub before updating every selected direct submodule
to its remote default tip. Report and dry-run calls do not initialize missing checkouts.

```powershell
.\scripts\windows\Invoke-Renovate.ps1                      # what is behind
.\scripts\windows\Invoke-Renovate.ps1 -Apply -DryRun       # the plan
.\scripts\windows\Invoke-Renovate.ps1 -Apply               # apply the plan
.\scripts\windows\Invoke-Renovate.ps1 -Managers pub        # narrow the managers
.\scripts\windows\Invoke-Renovate.ps1 -Recurse             # owned submodules, in place
```

`-Recurse` writes into the vendored submodules in place: commit and push each, then move the
gitlinks in every superproject that vendors it. How Renovate detects and `--apply` writes:
[`dependency-updates.md`](third_party/ANTfrastructure/docs/dependency-updates.md); this repo's
runner: [`docs/source/project-operations.md`](docs/source/project-operations.md) § *Dependency upgrades, in detail*.

## 6. Docs owned by this repo

**Write docs like a developer: short and precise** (owner, 2026-10-19). Say what a thing does,
how to run it and what breaks; no filler, no marketing, no repetition.

- Guides live in `docs/source/` as plain Markdown, published through exactly one
  builder: `scripts/linux/generate-docs.sh`, whose `DARTDOC_BUILD_GUIDES` array
  is the list of pages. There is no Sphinx site — the `sphinx-quickstart`
  scaffolding was deleted on 2026-09-15, unused by every lane
  ([`docs/source/project-operations.md`](docs/source/project-operations.md)
  § *There is no Sphinx site here*).
- **`docs.yml` builds and publishes that site** (2026-10-19): the hub's `build-docs.yml` runs
  `generate-docs.sh` in the image, fails on a dead internal link in `doc/api` and uploads it on
  a push to `develop` or `main`. The Linux lane builds no docs (`--run-docs false`). Detail:
  [`docs/source/project-operations.md`](docs/source/project-operations.md) § *Documentation Workflow*.
- [`docs/source/platforms.md`](docs/source/platforms.md) holds the full
  symptom→cause→fix table for containerized Windows builds.
- Update docs in the same PR as user-facing behaviour changes.
