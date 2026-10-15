# AGENTS.md

Guidance for coding agents (and new contributors) working in
OmniAccelerANT.

Laid out per ANTfrastructure's
[`shared/templates/AGENTS.md.template`](third_party/ANTfrastructure/shared/templates/README.md).
The rule that shapes it: *would this still be true in a different project?* If
yes, ANTfrastructure owns it and § 2 links to it. If no, it is written out in § 4.

## 1. What this project is

A Flutter/Dart app (`lib/`) targeting Windows, Linux, Android and web, with a
Rust core and a C++ inference plugin underneath it.

| Path | What lives there |
| --- | --- |
| `lib/` | The Flutter/Dart frontend |
| `third_party/OxidANT` | Rust core, bridged via `flutter_rust_bridge` — regenerate bindings with `flutter_rust_bridge_codegen generate` (a cargo binary baked into the build image, NOT a pub dependency; on a bare host `cargo install --locked --version <pin> flutter_rust_bridge_codegen` first, where `<pin>` is `FLUTTER_RUST_BRIDGE_VERSION` in the image or the `flutter_rust_bridge` version pinned in `third_party/OxidANT/Cargo.toml` (`=2.13.0` today) off it — a floating latest desynchronises the Dart bindings from the Rust runtime). `lib/src/rust/` is committed generated code — no build lane regenerates it |
| `packages/kataglyphis_native_inference` | C++ inference plugin — **plain files, not a submodule**; a `pubspec.yaml` path dependency. Links GStreamer + ONNX Runtime via CMake/pkg-config |
| `third_party/AccelerANTgine` | The inference core the plugin builds. Its own submodule, sibling to the plugin rather than nested inside it |
| `scripts/windows/`, `scripts/linux/` | Thin wrappers over ANTfrastructure drivers + this repo's own glue |
| `third_party/ANTfrastructure` | The submodule owning every reusable script, module and doc |

**Rust-owned webcam inference (Windows, and Linux since 2026-09-16).** The Stream
page runs a Rust-owned webcam → ONNX → Flutter-texture pipeline: `crates/media`
GStreamer capture → `src/webcam_engine.rs` → frb `src/api/webcam.rs` stream.
Frames reach the texture through the native plugin's `knt_push_frame` C ABI;
only detection metadata crosses the bridge. Gated by Rust features passed via
the `KATAGLYPHIS_RUST_FEATURES` env var, read at CMake configure time by
`rust_builder/<platform>/CMakeLists.txt` and handed to cargo through
`CARGOKIT_EXTRA_CARGO_FLAGS` — a local patch in `rust_builder/cargokit/`, which
is vendored here, **not** a submodule. The fourth argument to `apply_cargokit`
is *not* a features parameter on either platform; do not try to pass them there.
Windows uses `gstreamer,onnxruntime_dynamic,onnxruntime_directml`; DirectML is a
Windows-only execution provider, so Linux takes a different set. `mfvideosrc`
needs the `mediafoundation` GStreamer plugin **and** a Windows client host; it
falls back to `ksvideosrc`. Details in
[`docs/source/camera-streaming.md`](docs/source/camera-streaming.md)
§ *Rust-owned webcam inference*.

**Linux has this too as of 2026-09-16, and a frame has crossed it since 2026-10-05.** All four
links are in the tree: the `knt_push_frame`/`knt_api_version` C ABI exported
from the Linux plugin, `KATAGLYPHIS_RUST_FEATURES` forwarding, ONNX Runtime
bundling, and a Dart branch that routes Linux to `RustWebcamView` behind a
runtime `webcamInferenceAvailable()` probe — so a build with no features set keeps the C++
GStreamer MethodChannel path unchanged. The probe is a compile-time answer; never put
`listCameras()` back on that path, which starts libcamera and held the first frame 0.94 s
(2026-10-15). **This is an addition, not a
replacement**: the two paragraphs below stay true.

**A test-pattern frame travels Rust → `knt_push_frame` → texture on every native
lane run** (2026-10-05). `integration_test/webcam_frame_test.dart` starts
`RustWebcamView` on `videotestsrc` under Xvfb and polls the plugin's
`hasPushedFrame`, which reads the flag `knt_push_frame` sets. The capture half needs
no camera for that, since a camera only changes the source. A real camera on Linux is
still a manual check. The ABI is verified by `scripts/linux/check-knt-abi.sh`, which
dlopens the built plugin and checks the symbols and error codes. Since 2026-10-01 the
lane also starts the packaged bundle under Xvfb and drives
`integration_test/simple_test.dart` there (§ 5, *What each lane tests*). The lane sets
`KATAGLYPHIS_RUST_FEATURES=gstreamer,onnxruntime_dynamic` by default as of
2026-09-17 (empty string opts out), and the packaged artifacts carry their
GStreamer/ONNX Runtime/model closure, so the featureless app is no longer the
only Linux product.

**Linux/web cat detection stream.** The same Stream page consumes a WebRTC
stream produced by `third_party/OxidANT/crates/observant`
(`kataglyphis_observant`): V4L2/libcamera → ONNX (cat = COCO class 15) → boxes
burned into the RGBA frames → `webrtcsink` with its own signalling server.
`scripts/linux/observant/serve.sh` puts HTTPS (or, with `--http`, plain HTTP)
+ COOP/COEP + a `/webrtc-ws` proxy in front of it, so one build works on localhost, a LAN IP or a
Raspberry Pi; on a Pi 5 CSI camera the producer half is **OxidANT's**
`third_party/OxidANT/scripts/linux/observant/run-producer-pi.sh`, a Pi Zero
2 W runs the image with the same host-libcamera swap plus a `gst-launch` no-AI
pipeline (the Rust producer does not fit 512 MB), and a RISC-V SoC runs the
riscv64 variant natively with a USB webcam (`--v4l2`) — see § 2's glue list.
**The boards now run the installable ObservANT** (§ 2's glue list): producer, web build
and page together on `http://<board>:8080/`, under the package's systemd unit. The
container + `serve.sh` shape on `https://<board>:8444/` is the manual one, which the
Zero keeps; `serve.sh --producer-host` is only for looking at one board from another host.
Runbook: README § *Live cat detection stream*.

**`observant` is this app's only WebRTC producer.** AccelerANTgine carries a
second, unrelated one — `Src/webrtc_streamer.{ixx,cpp}`, reached only through
`cli_main.cpp`'s `--webrtc` flag, with its own GStreamer signalling on
`ws://127.0.0.1:8443`. It compiles into the `AccelerANTgine` shared library that
`packages/kataglyphis_native_inference` links, but nothing in this app calls it:
the plugin's own sources do not mention WebRTC at all, and the Stream page's
stream comes from the Rust crate. Two producers, one repo apart; do not wire
them together expecting a shared signalling path.

## 2. What ANTfrastructure owns — links only

**Do not restate these procedures here.** Start at
[`third_party/ANTfrastructure/docs/INDEX.md`](third_party/ANTfrastructure/docs/INDEX.md),
which maps topic → owning document, so these links survive upstream
reorganisation.

| Topic | Where |
| --- | --- |
| The winamd64 image — what it carries, its entrypoint, running it with `--isolation process` | `docs/windows-builds.md` |
| Stevedore setup and its post-install fixes | `docs/windows-host-setup.md` (Phase A), `docs/windows-stevedore-and-docker.md` |
| The two host fixes that stop this box's Windows containers idling at teardown: the patched runhcs shim, which every Stevedore update reverts, and `TcpTimedWaitDelay` at 30 s (reboot to take effect). `Install-NewHost.ps1` sets both and `Test-HostSetup.ps1` checks both (measured 2026-10-14) | `docs/windows-host-setup.md` § R1 and § C6, `third_party/ANTfrastructure/AGENTS.md` § *Stevedore Fixes After Install* |
| Isolation policy, and `docker commit` needing hyperv | `docs/windows-build-lanes.md` |
| An error message from either lane — symptom → cause → fix | `docs/failure-modes.md` |
| Bind mount vs tar-pipe, **Dev Drive filter setup**, container reuse, measured timings | `docs/windows-container-build-performance.md` |
| sccache on a C++20/23 modules build — the released one serves stale importers on clang-cl until mozilla/sccache#2876 ships | `docs/windows-container-build-performance.md` § *sccache on a C++23 modules build* |
| The image's pkg-config and rustup provisioning | `docs/windows-builds.md` (§ *Toolchain pins and the provenance manifest*, § *Rust toolchain*) |
| Wiring this repo to ANTfrastructure — resolver, actions, libraries | `docs/adopting-in-a-new-project.md` |
| Linux container builds | `docs/linux-build-basics.md` |
| Running the Linux lane locally on Windows (Rancher Desktop/nerdctl), and **a bind mount that resolves but is empty** — containerd's mount namespace, Windows vs WSL path form | [`docs/rancher-desktop-linux-containers.md` § *An empty mount is not a missing drive*](third_party/ANTfrastructure/docs/rancher-desktop-linux-containers.md#an-empty-mount-is-not-a-missing-drive) |
| Why WSL 3's `wslc` does not replace Rancher Desktop yet: no `--privileged`, `--platform` or `--device`, measured 2026-10-05 | [`docs/rancher-desktop-linux-containers.md` § *WSL containers*](third_party/ANTfrastructure/docs/rancher-desktop-linux-containers.md#wsl-containers-wslc-are-not-a-replacement-yet) |
| The five shell-safety bug classes | `third_party/ANTfrastructure/AGENTS.md` § *Shell safety conventions* |
| Code comments: one line, only the why; API docs short; gated | `third_party/ANTfrastructure/AGENTS.md` § *Comments: one line, only the why* |
| Searching the tree: `rg`, not `grep -r` | `third_party/ANTfrastructure/AGENTS.md` § *Searching the tree: ripgrep (`rg`)* |
| appimagetool provisioning — pinned version + SHA256, not the moving `continuous` tag | `linux/scripts/02-toolchain/packaging-deps.sh`, subcommand `appimagetool` |
| Python venv + `uv` provisioning (installer downloaded to a file and SHA-checkable, never `curl \| sh`) | `linux/scripts/01-core/python_uv.sh` |
| The Dart gate for Linux lanes — deps, format, analyze, test, `--strict`/`--extra-package` | `linux/scripts/05-frameworks/flutter/flutter_checks.sh` |
| The CMake gate's machinery — `code_quality_find_cmake_files` + `CODE_QUALITY_CMAKE_EXCLUDE_PATHS` on Linux, `Initialize-UvVenv` + `Install-UvRequirements` on Windows | `linux/scripts/lib/code-quality.sh`, `windows/scripts/modules/WindowsUv.Common.psm1` |
| The canonical `.cmake-format.yaml` this repo's root copy syncs from, and the drift check | `shared/config/README.md` |
| **Image and tag naming** — one published tag = one manifest over every arch of its variant; `:latest` (linux) / `:winamd64` (windows), variants `:latest-<variant>` (`nvidia`, `rocm`) only for a stack that cannot ship in `:latest`, per-arch tags are internal wrappers; Windows' arm64 output is a bundle, not a `windows/arm64` platform | `third_party/ANTfrastructure/AGENTS.md` § *Image and tag naming* |
| **Every checkout on its branch tip** — this repo and every submodule, third-party ones included, recursively, fast-forward only; no gitlink is committed (`linux/scripts/git-sync-branches.sh`) | `docs/adopting-in-a-new-project.md` § *Putting every checkout on its branch* |
| Dependency upgrades — Renovate as a local CLI, why `--platform=local` only detects, the pinned Node/Renovate bootstrap, why `--apply` refuses a branchless submodule | `docs/dependency-updates.md` |

Two upstream facts repeated here only because they bite before you reach a doc:

- Every ANTfrastructure PowerShell module declares `#requires -Version 7.0`, so
  `Build-Windows.ps1` and `Start-Windows.ps1` do too — launch with `pwsh`, never
  `powershell`. Under 5.1 it fails as an opaque `Import-Module` error.
- Composite actions resolve at `@develop`, so a ANTfrastructure change a workflow
  depends on must be pushed **before** the consumer change.

**This repo's glue** (deliberately thin):

- `scripts/windows/Resolve-BuildModule.ps1` — the one file that cannot live
  upstream, because it is what *finds* the submodule. `Import-BuildModule <Name>`
  checks ANTfrastructure first, then `scripts/windows/modules/`, which holds only
  genuinely project-specific modules (today: `WindowsPaths.Common`, encoding this
  repo's Flutter `build/windows/x64/{runner,plugins}` layout;
  `WindowsOrtRunner.Common`, which stamps the hub's G6 verdict on the chain ONNX
  Runtime the hub's `WindowsOrtPayload.Common` stages into that runner — § 4;
  `WindowsLaneGuard.Common`, one lane at a time per checkout — § 5; and
  `WindowsFlutterAot.Common`, which catches a stale AOT target that `assemble` calls up
  to date).
- `scripts/linux/lib/antfrastructure.sh` — the bash twin: `antfrastructure_source`
  and `antfrastructure_path`, resolved from `${BASH_SOURCE[0]}` so they work from
  any working directory.

  Both are copies of the hub's templates (`shared/windows/templates/`,
  `shared/linux/templates/`), declared in `.antfrastructure-shared.manifest` and
  compared with them in `body` mode by the shared-config drift gate, so a change
  goes into the template upstream, never into the copy alone.
- `scripts/agentic-loop/` — the adopted planner/executor loop: config, both
  runner wrappers, prompt overlays. Engine `opencode` (**v2 only**), executor
  `opencode-go/deepseek-v4.1-flash`. Its Windows build/test driver is
  `scripts/windows/Build-Windows-Container.ps1`. Rules and commands: § 5.
- `scripts/linux/observant/serve.sh` — serves the web build over TLS (`--http`:
  plain HTTP, no certificate) with COOP/COEP for the Rust core and proxies `/webrtc-ws` to the cat producer.
  No container involved; it is the deployment half of the demo.
  `--producer-host`/`--producer-port` front a producer on another board and
  `--state-dir` keeps concurrent instances apart.
- `third_party/OxidANT/scripts/linux/observant/run-producer-pi.sh` — **not in
  this repo.** It moved to OxidANT under decision D12, which owns the
  `observant` crate it builds and starts; this repo keeps the pointer, not a
  copy. It runs the cat producer from the image against a Pi 5 CSI camera
  (`--libcamera`), bind-mounting the host's Raspberry Pi OS libcamera stack
  ahead of the image's outdated upstream copy (the kernel 6.18 `rp1-cfe`
  entity rename + libpisp 1.7). `--build` builds the producer first;
  `--libs-only` refreshes the cached library closure. `serve.sh` above is the
  half that stays here, because the Flutter web build is this repo's.
- `scripts/linux/observant/package-producer-bundle.sh` — container-less
  fallback for boards that cannot run the image comfortably (Pi Zero 2 W):
  exports the producer, a pruned GStreamer subset, the image's glibc (invoked
  through the bundled loader) and the library closure into
  `build/observant/pi-bundle/` (~180 MB, aarch64). The target only needs
  libcamera installed; `--deploy HOST` rsyncs it there. Its ONNX Runtime is the
  image's chain copy, and the same image run proves the finished bundle with
  ANTfrastructure's G6 census before anything leaves the container.
- `scripts/linux/observant/package-observant.sh` + `package/` — the installable ObservANT
  (2026-10-05): producer, plugins, chain ORT, model, web build and the image's loader and libc
  in `/opt/omni-observant`, as a `.deb` (systemd unit, ufw profile), an AppImage and a flatpak;
  riscv64 gets the `.deb` and a tarball, built on the board. **`observant.toml` is not a
  conffile, on purpose**: an edited one stopped upgrades at dpkg's prompt, so `setup` writes it
  `640 root:omni-observant` only when it is absent. `package/*` is pinned to LF. Detail:
  [`docs/source/camera-streaming.md`](docs/source/camera-streaming.md) § *The ObservANT package*.
- `scripts/windows/observant/` — the Windows ObservANT, built and tested in `:winamd64`
  (2026-10-06): `Package-ObservANT.ps1` makes the install folder, the zip, the MSI and, with
  `-Msix`, a signed MSIX (an unsigned one fails the build); `Test-ObservANTWindows.ps1` and
  `Test-ObservANTMsix.ps1` check them. **openh264 is a required plugin on Windows**, since the
  image builds no `vpx`. Detail: [`docs/source/camera-streaming.md`](docs/source/camera-streaming.md) § *The Windows ObservANT*.

**Deliberately not reused.** Two upstream Windows pieces were evaluated and
rejected — `WindowsAppRunner.Common` (its executable probe would launch the
wrong one of this tree's four runner exes and ignore `-Configuration`) and
`Invoke-CmakeConfigureAndBuild` (mandatory `-Preset`, no `-S`, no `--target`,
and it fuses configure and build while the `Native Assets Directory Fix` step
must run between them). Both would be regressions here, so do not "fix" their
absence; the full reasoning is in
[`docs/source/platforms.md`](docs/source/platforms.md)
§ *Windows pieces deliberately not reused*.

## 3. Critical invariant: submodule pins

Builds are only supported against the **recorded submodule gitlinks** — the
commits CI builds green. There are four:
[`third_party/ANTfrastructure`](third_party/ANTfrastructure) (the hub, § 2),
[`third_party/OxidANT`](third_party/OxidANT) (the Rust core behind
flutter_rust_bridge), [`third_party/AccelerANTgine`](third_party/AccelerANTgine)
(the inference core the Windows and Linux plugin builds link) and
[`third_party/ANThology`](third_party/ANThology) (the shared Dart package).
`git submodule update --checkout --recursive` restores them. If a drifted
checkout is what you actually want, move the gitlink **and** fix the fallout in
the same change — a working tree that has quietly walked forward from its
gitlink is compiling something other than what is committed, and `git submodule
status` marks that only with a `+`.

The opposite move, for local work on the newest code, is
`bash third_party/ANTfrastructure/linux/scripts/git-sync-branches.sh` (`--dry-run`
first): every checkout goes to the tip of its `branch =`, the vendored
third-party libraries under AccelerANTgine included (owner decision 2026-10-07).
FUZZTEST stays on a release because AccelerANTgine declares
`branch = release_<date>` for it; move that line to take a newer release. It
leaves exactly that `+`; commit the gitlinks innermost repo first. One `+` cannot
be committed from here: nanobind's `ext/robin_map`, which only nanobind records. The next `git submodule update`, or a git GUI that runs one, puts the
submodules back unless the gitlinks are committed: on 2026-10-07 one reset three
submodules two minutes after they were moved.

Drift is guarded by ANTfrastructure's shared Pester suite, run from
[`.github/workflows/submodule-pins.yml`](.github/workflows/submodule-pins.yml)
after any pin bump. It checks both directions: each checkout sits at the
recorded commit, and the recorded commit is reachable from that submodule's
remote — a gitlink bumped to a commit that was never pushed builds on the
machine that made it and on no other.

**Submodule URLs are `https://github.com/Kataglyphis/<repo>.git`, all four.**
Not `git@github.com:`. An ssh remote needs a key, and none of the places that
have to resolve these has one: a CI runner, the `:latest` container the
Renovate runner starts, and anyone cloning the repo without a GitHub account.
`git submodule update --init` then fails with `Permission denied (publickey)` on
a repository that is public. `git config -f .gitmodules submodule.<path>.url …`
is the way to change one; follow it with `git submodule sync` so the existing
checkout's remote moves too.

**What nothing here asserts:** `AccelerANTgine` and `OxidANT` each carry a
`third_party/ANTfrastructure` pin of their own, free to differ from this repo's.
Bumping the hub here does not bump the hub those two build against; that has to
happen in their own repositories.

## 4. Pitfalls specific to this project

Everything here is false or meaningless in another repo — that is why it is
written out rather than linked.

- **Three scripts print a fixed line range of their own header as `--help`.**
  `scripts/linux/observant/package-producer-bundle.sh` (`sed -n '2,22p'`),
  `scripts/linux/observant/package-observant.sh` (`sed -n '2,15p'`) and
  `scripts/agentic-loop/Run-AgenticLoop.sh` (`head -30 | tail -28`): edit the
  header and the range together.
- **The two bootstrap copies are body-mode assets.** Below their header,
  `scripts/linux/lib/antfrastructure.sh` and `scripts/windows/Resolve-BuildModule.ps1`
  must equal the hub templates byte for byte (`sync-shared-config.sh --check`).
  Re-copy them from the templates after an upstream change; never edit them here.
- **Six image gaps this repo once worked around are fixed in the image (2026-09-05); never
  bring a workaround back.** A reappearing one is an image regression ([`docs/source/platforms.md`](docs/source/platforms.md)
  § *Image gaps and image-tag history*). What stays here is `setup_compiler_cache`, which points
  `RUSTC_WRAPPER` and the CMake launchers at the hub's guarded `sccache-launcher.sh`.

- **The Android GStreamer SDK is in the image, and the image now announces it.**
  It sits at `/opt/android/gstreamer` as a flat prefix (`gst-android/ndk-build`,
  `include/`, `lib/`). Without `GSTREAMER_ROOT_ANDROID` the native plugin's
  `CMakeLists.txt` stops the Android lane at configure time with
  `GSTREAMER_ROOT_ANDROID must be set`; the plugin accepts both the per-ABI and
  the flat layout, so the path alone is enough. The hub's `linux/Dockerfile.package`
  sets `ENV GSTREAMER_ROOT_ANDROID=/opt/android/gstreamer` (checked in the published
  `:latest` amd64 config, 2026-10-01). The image used to ship the SDK without the
  variable, and `export_android_gstreamer_env` probed and exported it here until
  2026-10-01, a no-op in CI since run 36154744222. If the configure error comes back,
  the image lost its `ENV`: fix the image, do not bring the probe back.

- **Every Android SDK component is pinned to what the image ships**, in one place: the `extra`
  block of `android/build.gradle.kts` (compileSdk 37, build-tools 37.0.0, NDK 29.0.14206865, CMake
  4.1.2, and the APK's one ABI). `/opt/android-sdk` is read-only, so anything else stops Gradle
  with `The SDK directory is not writable`. Detail, and why the override sits above
  `evaluationDependsOn(":app")`: [`docs/source/platforms.md`](docs/source/platforms.md) § *Android SDK components pinned to the image*.

- **The image's clang selects its own GCC; nothing here injects `--gcc-toolchain`
  any more.** Since `:latest` of 2026-09-29 (hub CON16) a bare `clang`/`clang++`
  reads `<native-triple>-clang{,++}.cfg` beside it, which names the source-built
  GCC 16.2.0. Before that it picked the distro GCC and the link died, which is
  why `export_toolchain_env` injected the flag for months. It now only sets
  `CC=clang CXX=clang++` and **refuses** a clang that selects anything but
  `gcc_toolchain_resolve_prefix()`'s GCC: an image older than CON16 fails there,
  loudly, instead of at the link. Do not put the flag back to "fix" that; pull
  the image. History and measurements:
  [`docs/source/platforms.md`](docs/source/platforms.md)
  § *Android and cross-toolchain constraints*.

- **Editing a lane script while its container runs makes the log lie.** bash
  sources `container-steps.sh` once at start, so a later edit does not take
  effect — but the log then shows behaviour that no longer matches the file on
  disk, and the next reader (including you, ten minutes on) draws the wrong
  conclusion. This cost one run: the log said "falling back to bare clang" while
  the file already had the fix. Wait for the container to exit.

- **The flatpak gets `--device=all`, because flatpak has no `--device=video`**
  (owner, 2026-10-01). `scripts/linux/lib/packaging-common.sh` sets
  `KATAGLYPHIS_FLATPAK_FINISH_ARGS`, which the hub appends to its four finish-args,
  and `package-linux.sh` prints the built app's `[Context]` and fails when an
  appended argument is missing from it. An empty value drops it.

- **A packaged Linux artifact carries its whole runtime closure**: every bundled ELF has its own
  `$ORIGIN` RUNPATH (RUNPATH is not transitive), the GStreamer libraries and seven plugins travel
  in `bundle/lib`, and ORT is the image's chain build, proven by the hub's G6 census in
  `check-bundle-closure.sh`. With the lane's Rust features ORT is in `bundle/lib` before the packer
  runs (`Kept (already in bundle/lib, not copied)`), so a copy list without ORT is not a missing
  ORT. Detail: [`docs/source/camera-streaming.md`](docs/source/camera-streaming.md) § *Relocatable Linux bundles*.
- **The Rust binaries name the chain ORT's directory, and G6 must read them as importers.**
  OxidANT's loader keeps `/opt/onnxruntime/onnxruntime/core/` as a string, so only a whole
  NUL-terminated `__FILE__` path is an ORT fingerprint. A census calling `liboxidant.so` or
  `oxidant.dll` `UNPROVEN` or `STALE` is a hub pin older than e72a9a37: move the pin, never
  OxidANT. Detail: [`docs/source/camera-streaming.md`](docs/source/camera-streaming.md) § *Relocatable Linux bundles*.

- **Rust `i64` is `int` natively and `BigInt` on web, so only the web lane
  catches the mismatch.** flutter_rust_bridge maps it to `PlatformInt64`, a
  typedef that resolves per platform, and app code that passes a plain `int`
  compiles everywhere except web:
  `Error: The argument type 'int' can't be assigned to the parameter type
  'BigInt'` — from `rust_webcam_view.dart`, a widget for the native path (then
  Windows only, Windows and Linux now). Wrap the value in `PlatformInt64Util.from(...)`,
  which is the identity on native. It lives in
  `package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart`, not in
  the public `flutter_rust_bridge.dart`, and importing the generated binding
  does not bring it along — Dart does not re-export transitively.

- **The web lane builds the wasm core with the image's dated nightly and its `rust-src`**
  (`RUST_NIGHTLY_TOOLCHAIN` from the pinned hub's `versions.env`), never the floating `nightly`,
  which downloads a channel each run and dies on the image's read-only layer. Detail: [`docs/source/project-operations.md`](docs/source/project-operations.md)
  § *The web lane's nightly toolchain*.

- **The web lane installs `flutter_rust_bridge_codegen` only when the image has
  none.** `:latest` ships the binary at `FLUTTER_RUST_BRIDGE_VERSION`,
  which it also exports; the unconditional `cargo install` that used to sit
  here rebuilt 174 crates on every CI run and then failed the lane. The guard
  is `command -v` plus `cargo install --locked --version "${FLUTTER_RUST_BRIDGE_VERSION}"`,
  so a bare host gets the same pin the image carries — never a floating latest,
  and never `--force`.

- **Renaming the Rust crate touches committed generated code.**
  `lib/src/rust/frb_generated.dart` hard-codes the artefact name in
  `kDefaultExternalLibraryLoaderConfig`: `stem` (`oxidant` → `oxidant.dll`,
  `liboxidant.so`, `pkg/oxidant.js`) and `ioDirectory`
  (`third_party/OxidANT/target/release/`). No lane regenerates that file, so a
  `[lib] name` change in `Cargo.toml` stays silent until the app fails to load
  its library at runtime. Windows repeats the name a second time in
  `scripts/windows/Get-WindowsBuildConfig.ps1` (`RustDllName`,
  `RustPluginSubDir`). Change all three together.

- **Models are fetched, never tracked** (owner, 2026-10-14). The detector is DEIM-D-FINE-N
  (Apache-2.0), released by [ModelANT](https://github.com/Kataglyphis/ModelANT);
  `third_party/OxidANT/resources/models/models.lock` pins each file's URL and SHA-256, and
  `third_party/OxidANT/scripts/linux/fetch-models.sh` (`--dest DIR`; Windows:
  `scripts\windows\Get-Models.ps1`) is the only way in. A checkout has no model until it
  runs, so the Rust webcam view on a dev build fails to load one: the native lane runs it
  before the build, the bundle and package scripts call it themselves. A new model goes
  into ModelANT and only the lock moves here; the old AGPL files stay in the history.
  Detail: `docs/source/camera-streaming.md` § *The detection model*.

- **The app version is written twice, and both move together.** `version:` in
  `pubspec.yaml` stamps the `.deb`, AppImage and flatpak names;
  `msix_config.msix_version` is the MSIX's, with its fourth field held at 0 for
  the Store. `test/pinned_artefacts_test.dart` fails when they drift. 2.0.0+2
  (2026-10-01) is a major bump over the `1.1.0+1` tag: the 2026-09-05 rename
  changed the package name, the executable, the Linux application id and the MSIX
  identity (`Kataglyphis.KataglyphisInferenceEngine` → `Kataglyphis.OmniAccelerANT`),
  so a 1.x install does not upgrade in place. `CHANGELOG.md` holds the rest.

- **`dbName` in `lib/src/db/sqlite3_loader_web.dart` is deliberately NOT the
  package name.** It still reads `kataglyphis_inference_engine` after the
  2026-09-05 rename to `omni_accelerant`, because it names the **IndexedDB
  database in the visitor's browser**, which backs the sqlite3 VFS. Changing it
  does not rename anything — it opens a *different, empty* database and orphans
  whatever the visitor had, with no error and no migration path. A rename here
  is a data migration, not a naming change, and it needs a copy step first. The
  string is invisible to everyone except the browser, so leaving it costs
  nothing. It also happens to be what keeps that call wrapped across three
  lines; the shorter name fits on one and `dart format` then rewrites the file.

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

- **Never `dart format .` here.** It ignores `analysis_options.yaml` entirely,
  so the recursive walk reaches `flutter/`, `third_party/` and `build/` — one
  run reported `Formatted 7404 files (627 changed)` and rewrote the Flutter SDK
  on disk on the way. Both lanes list tracked files instead
  (`code_quality_find_dart_files` on Linux, `Get-ProjectDartFiles` on Windows;
  the same list, `git ls-files -- '*.dart' ':!:rust_builder/**'`). Keep the tracked-file listing even though the SDK now
  comes from the image. `dart analyze` is *not* affected and never was. Detail:
  [`docs/source/project-operations.md`](docs/source/project-operations.md)
  § *Static checks*.

- **A single-arch image tag looks exactly like broken code.** `:latest` (then `:latest-cross`)
  was an amd64-only tag until 2026-09-04, so the arm64 matrix row ran x86-64
  binaries (`rustc: 1: ELF: not found`) and nothing in this repo could work
  around it. The tag is a proper OCI index now. Two habits survive the hunt:
  the architectures stay independent — `fail-fast: false` did that while they
  were one matrix, and since 2026-09-24 they are two workflows
  (`linux-x64.yml`, `linux-arm64.yml`), independent by construction — and a
  `Failed to pull` line in a log is usually GitHub **echoing the retry
  script's source**, not running it.
  Write-up: [`docs/source/platforms.md`](docs/source/platforms.md)
  § *Image gaps and image-tag history*.

- **ASAN works, but only against Microsoft's runtime** — LLVM's loads after
  ucrtbase and aborts `bad-free` on the COM startup allocations a Flutter app
  makes, which is why `Start-Windows.ps1` stages the MSVC DLL and why no `/MT`
  override may exist anywhere. The runtime choice, the linked thunk pair and the
  `ASAN_OPTIONS` are ANTfrastructure's:
  [`docs/windows-clang-cl-sanitizers.md`](third_party/ANTfrastructure/docs/windows-clang-cl-sanitizers.md).
- **The clangcl-Debug preset ships with ASAN ON** and builds + runs green (Dart
  VM up, camera live). Historic gotchas, all fixed: naive ASAN dragged `/MT`
  into Flutter's `/MD` objects (`lld-link` RuntimeLibrary mismatch), and
  `kataglyphis_libfuzzer.exe` hit an `annotate_string` mismatch vs
  `clang_rt.fuzzer`.
- **Each Windows preset installs into its own `runner\<preset>\`** (and `plugins\<preset>\`);
  `Start-Windows.ps1 -Configuration` must name the same preset, and
  `x64-ClangCL-Windows-Release` is only the fallback. `runner\Release` is the MSIX copy of the
  first preset built.
- **ONNX Runtime in a Windows runner is the image's chain build, staged by the build and proven
  by the hub's G6** (owner rule 2026-09-23); never copy an ORT into a runner by hand.
  `Start-Windows.ps1` refuses a runner whose ORT is missing, unstamped, changed or foreign, since
  Windows would otherwise load System32's Windows ML 1.17. Detail: [`docs/source/platforms.md`](docs/source/platforms.md) § *ONNX Runtime in
  the Windows runner*.
- **On an unprovisioned host** (`STATUS_DLL_NOT_FOUND`, or a ~6 MB process that exits) the
  runner lacks the image's runtime DLLs: stage `C:\runtime\bin` and its GStreamer plugins, put
  `runner\bin` (`AccelerANTgine.dll`) on `PATH` as `Start-Windows.ps1` does, and install the
  VC++ runtime. Symptom table: [`docs/source/platforms.md`](docs/source/platforms.md) § *Troubleshooting containerized Windows builds*.
- **Dart file ops fail on bind-mounted paths.** `copySync`/`renameSync` fail
  (plain writes and cmd `copy`/`ren` work), so junction `.dart_tool` and `build`
  from the mounted workspace to container-local dirs before building. The
  bind-mount setup itself is upstream's — see § 2.
- **The native plugin needs pkg-config** and the image's baked
  `PKG_CONFIG_PATH` (GStreamer/FFmpeg/OpenCV `.pc` files under `C:\runtime`).
  Whether the image ships a pkg-config binary is upstream's problem; needing it
  is ours.
- **Cargokit hard-requires rustup.** The `rust_builder` Flutter plugin builds
  its crate via Cargokit during CMake install, and Cargokit will not use a
  scoop-only Rust. Install rustup **with a default toolchain**; only
  toolchain-less rustup shims are harmful. The winamd64 image provisions exactly
  that now (hub `docs/windows-builds.md` § *Rust toolchain*), so this bites only
  outside it.
- **Cargokit builds `liboxidant` with the toolchain rustup resolves for OxidANT, never a
  floating `stable`**: a local patch in `rust_builder/cargokit/build_tool/lib/src/`
  (`builder.dart`, `rustup.dart`), both halves kept when bumping the vendored copy.
  `check-rust-toolchain.sh` fails the native and Android lanes on any other `rustc version`
  stamp. Detail: [`docs/source/platforms.md`](docs/source/platforms.md) § *Cargokit's Rust toolchain*.
- **The Linux plugin builds AccelerANTgine without its test suites and its Debug sanitizers**
  (`BUILD_TESTING` and both `myproject_ENABLE_SANITIZER_*` OFF before `add_subdirectory`):
  without them the Debug integration build cannot link. Windows keeps its ASan Debug preset on
  purpose. Detail: [`docs/source/platforms.md`](docs/source/platforms.md) § *The Linux plugin's AccelerANTgine build*.
- **Vendored ANTLR** (pulled in unconditionally by newer FUZZTEST) needs
  `WITH_STATIC_CRT OFF`, `ANTLR_BUILD_CPP_TESTS OFF`, `ANTLR_BUILD_SHARED OFF`,
  `/FIchrono`, and `LICENSE.txt` staged at the build root — its install rule
  assumes a monorepo layout. Wired up in
  `third_party/AccelerANTgine/third_party/CMakeLists.txt` — the inference core's
  own dependency list, not the plugin's.
- **The Stream page needs no secure context.** Only the Rust wasm core wants cross-origin
  isolation, and on web `main()` treats a failed `RustLib.init()` as optional, so Firefox and
  Safari over plain HTTP still boot; only the About page's Rust demo goes dark. `serve.sh
  --http` serves that, and without `--http` it ends TLS on 8444 in front of the producer. Detail:
  [`docs/source/camera-streaming.md`](docs/source/camera-streaming.md) § *No secure context needed*.
- **`signalingServerUrl` may be host-relative, and only web resolves it.** A
  value starting with `/` (the committed `/webrtc-ws`) becomes
  `wss://<page-host>/webrtc-ws` in `WebRTCSettings.fromJsonFile`
  (`lib/settings/webrtc_settings.dart`); absolute `ws(s)://` URLs pass through
  untouched, as does everything on native, where the value is unused
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
- **The frb Dart bindings must match the Rust runtime's frb version.** They
  were stale at 2.12.0 against 2.13.0 and the web build died with an empty
  `Uncaught` before `pkg/oxidant.js` loaded. Regenerate both sides together:
  `flutter_rust_bridge_codegen generate` writes `lib/src/rust/` **and**
  OxidANT's `src/frb_generated.rs`; when the wasm artefacts are involved,
  `flutter_rust_bridge_codegen build-web --release --rust-root
  third_party/OxidANT`. `web/pkg/` is generated and gitignored.
- **The `environment: sdk:` floor picks `dart format`'s style, and two
  generators format with it.** At language version 3.13 the formatter puts a
  blank line between import groups, so moving the floor from 3.11.4 to 3.13.0
  (2026-10-11) reformatted ten tracked files, and the lanes' format gate failed
  until they were committed (429fef3, reverted in fafa9f3).
  `flutter_rust_bridge_codegen generate` and `flutter gen-l10n` run `dart
  format` on their output at that same language version. After a floor move,
  regenerate `lib/src/rust/` and `lib/l10n/` in the image rather than
  hand-format them; what they write then passes the gate unchanged. The image
  carries no `cargo-expand`, so the codegen installs it on first use and needs
  network.
- **Windows host only: the webcam reaches WSL over usbipd, and WebRTC needs
  mirrored networking.** `usbipd attach --wsl --busid <id>` (bus ids change)
  plus `modprobe uvcvideo` gives the container `/dev/video0`;
  `[wsl2] networkingMode=mirrored` in `%USERPROFILE%\.wslconfig` is what makes
  UDP media work — NAT mode drops it, and the port mapping looks fine until
  the stream never arrives. Both vanish on a WSL restart. `nerdctl pull` of a
  Docker Hub image can also fail on credential lookup (`A specified logon
  session does not exist`); pulling from inside the VM with an empty
  `DOCKER_CONFIG` is the workaround that worked.

## 5. Build, run, test

**Both lanes run the same thing locally and in CI; reproduce locally first, CI is not a
debugger.** **Run one lane at a time**: every local lane bind-mounts the same checkout and its
per-host generated files (`android/local.properties`, `.dart_tool`, the plugin symlinks), so two
at once break each other with errors that name neither. CI never sees this.

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
  has** (`C:\workspace` fails with `hcs::CreateComputeSystem`).
- **On the dev box, junction first**: start without the root and plugin `.dart_tool`/`build` and
  junction those four to container-local directories, or Dart's and CMake's write-then-rename
  steps fail on the mount. `Build-Windows-Container.ps1` streams the sources in and needs neither.
- **A failed step does not abort the run**, and the log still ends with `=== Build Complete ===`:
  trust the exit code and `failedSteps` in `logs/build-summary-*.json`, never the log tail.
- Presets `clangcl-{debug,profile,release}`, `msvc-{debug,release}`, `clang-{debug,profile,release}`;
  switches `-SkipTests`, `-SkipFormat`, `-SkipDocs`, `-CleanBuild`, `-SkipMsixPackaging`,
  `-SkipBootstrapFlutterBuild`, `-ContinueOnError`/`-StopOnError`, `-CodeQL` (the closing
  Delivery Check cannot be skipped). Logs in `logs/`, API docs in `doc/api`.
- **MSIX packaging runs only locally**: CI passes `-SkipMsixPackaging`, and `runner\Release` is the
  flat copy of the first preset that msix reads.
- **CI** ([`windows-x64.yml`](.github/workflows/windows-x64.yml)): the hub's PowerShell lint on the
  host before the ~54 GB image pull, the Release build with the lane's quality gates, four host
  checks of the runner (C ABI, plugin gtest, import walk, launch smoke with the ORT stamp), and
  `build-clang-debug`, which builds the ASan Debug app and its integration twin in one container
  (`Build-WindowsDebugApps.ps1`) for the launch smoke and `flutter drive`. The checkout prunes
  `third_party/DocumANTation` (`'$GIT_DIR' too big`), so every path is absolute under the
  short-path clone.
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

Owner goal 2026-10-01: every test runs on every lane that can host it. A blank
cell is a test that cannot run there, and the reason is under the table.

| Test | Linux x64 / arm64 | Windows x64 | Windows arm64 | Android | Web |
| --- | --- | --- | --- | --- | --- |
| App Dart tests (`test/`) | yes | yes, in the image | yes, arm64 Dart VM | yes | in Chrome |
| Plugin Dart tests (`packages/kataglyphis_native_inference/test/`) | yes | yes, in the image | yes, arm64 Dart VM | yes | in Chrome |
| Plugin gtest (`kataglyphis_native_inference_test`) | yes | built in the image, run on the host | yes, on the device | | |
| Plugin C ABI (`knt_*`) | `check-knt-abi.sh` | `Test-KntAbi.ps1`, host | `Test-KntAbi.ps1`, device | | |
| G6 over the shipped tree | `check-bundle-closure.sh` | at build, again on the host | at the natives build, again on the device | | |
| Bundle gate's mutation suite | yes | | | | |
| Dart coverage of `lib/` against a floor (`check-dart-coverage.sh`), and its synthetic-lcov suite | yes | | | | |
| Plugin C++ format (`check-plugin-cpp-format.sh`) and its planted-deviation suite | yes | | | | |
| Import walk | (the closure gate) | host, `-Standalone` | device | | |
| Launch smoke, 20 s | under Xvfb | host | device | | |
| Integration test (`integration_test/simple_test.dart`) | under Xvfb | `flutter drive` against the clang-cl app | `flutter drive` (the Debug app) | | |
| Webcam frame through `knt_push_frame` (`integration_test/webcam_frame_test.dart`) | under Xvfb, test pattern | | | | |
| Frame timings in profile mode (`integration_test/performance_test.dart`, `flutter drive --profile`), against the last default-branch run, and its scripts' suite (`test-perf-reports.sh`) | x64, under Xvfb | | | | |
| Pester (`scripts/windows/tests`) | | `windows-2025` | `windows-11-arm` | | |
| Plugin JVM test | | | | yes | |
| APK ABI gate (`check-apk-abi.sh`) and its synthetic-APK suite | | | | yes | |
| `liboxidant`'s rustc stamp (`check-rust-toolchain.sh`) and its suite | yes | | | yes, in the APK | |
| APK on the emulator, 20 s (`check-apk-on-emulator.sh`) and its stub suite | | | | yes, API 35 x86_64 + ARM translation, on KVM | |
| ObservANT .deb, AppImage and flatpak install checks (`test-observant-package.sh`) | | | | | in `web.yml`'s `observant` jobs, x64 and arm64 |
| ObservANT MSI install checks (`Test-ObservANTWindows.ps1`) | | | | | in `web.yml`'s `observant-windows` job, in `:winamd64` |
| ObservANT MSIX package checks (`Test-ObservANTMsix.ps1`, without `-Install`) | | | | | in `web.yml`'s `observant-windows` job, in `:winamd64` |

A blank cell is a test that cannot run there; why, lane by lane: [`docs/source/testing.md`](docs/source/testing.md) § *Why a lane
cannot run a test*. Two rules from there bite on every push:

- **A docs-only push** (`docs/**`, root `*.md`) runs Linux x64 alone, which deploys the docs; pull
  requests always run everything.
- **A push to `develop` cancels the round in flight**, so batch: commit locally and push when the
  round on `origin/develop` has finished (`gh run list --branch develop --limit 8`).

### The Dart gate in 23 seconds, without a lane

The Windows dev box has no Flutter SDK, but the image has one: the Dart gate alone against a
bind-mounted checkout takes 23 s warm. It is not the lane (no build, no CMake gate, no Rust or
C++); use it to iterate, and the lane to believe the result.

```powershell
# once: the cache volume must belong to the container's uid, like every other
# volume this repo mounts — see Invoke-LinuxLane.ps1's chown step. The image
# does the chown itself: no stock image, not even alpine (owner rule 2026-10-05).
nerdctl run --rm --platform linux/amd64 --user root --entrypoint chown `
  --mount "type=volume,source=oa-fastloop-pub,target=/vol" `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest -R 1001:1001 /vol

# then, per edit:
nerdctl run --rm --platform linux/amd64 `
  -v "C:\GitHub\OmniAccelerANT:/workspace" -w /workspace `
  --mount "type=volume,source=oa-fastloop-pub,target=/pubcache" -e PUB_CACHE=/pubcache `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest `
  bash -lc 'export PATH=/opt/flutter/bin:$PATH; git config --global --add safe.directory "*"; flutter test'
```

`scripts/windows/Invoke-DartChecks.ps1` is the same loop as a script (`-SkipFormat`,
`-SkipAnalyze`, `-SkipTest`, `-Fix`, `-Engine wslc`). Detail: [`docs/source/project-operations.md`](docs/source/project-operations.md) § *The Dart gate without a lane*.

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
.\scripts\windows\Invoke-LinuxLane.ps1 -SkipDocs                        # native, x64
.\scripts\windows\Invoke-LinuxLane.ps1 -Lane android
.\scripts\windows\Invoke-LinuxLane.ps1 -Lane web
.\scripts\windows\Invoke-LinuxLane.ps1 -Arch arm64                      # needs QEMU, see below
.\scripts\windows\Start-Windows.ps1 -Configuration x64-ClangCL-Windows-Release  # run a Windows build
```

- **One lane at a time** (above): a real run refuses while another lane's container or a
  Windows build is up (`-Force` overrides; `WindowsLaneGuard.Common`).
- **Everything write-heavy stays off the host mount.** A Windows bind mount refuses `utime`,
  `chmod` and `fchmod`, each with a different misleading error, so the build tree, pub's cache
  and cargo's target live on named volumes, the flatpak work under `/tmp/flatpak-work`, the
  compiler caches where the image puts them; only finished artifacts go to `out/`.
- **`-v name:/path` is a bind mount on Windows nerdctl**: spell a volume `--mount
  type=volume,source=…,target=…`.
- **An empty mount** means `D:` is missing from containerd's own mount namespace (gone after
  every VM restart) or the path was the WSL form; pass the Windows path (`D:\…`).
- **A `pubspec.lock` older than a workspace member's `pubspec.yaml` reds the web lane**
  (`Failed to set file modification time`): touch the lock on the host and rerun.
- **The android lane boots an emulator**: load KVM into Rancher's VM once per boot, or pass
  `-EmulatorSmoke false`.
- **arm64 needs QEMU registered once per VM boot**, and an emulated run makes tar and deb only.
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
turn. Nothing in CI runs it. On this host, in the family Linux image:

```powershell
.\scripts\windows\Invoke-Renovate.ps1                      # what is behind
.\scripts\windows\Invoke-Renovate.ps1 -Apply -DryRun       # the plan
.\scripts\windows\Invoke-Renovate.ps1 -Apply               # apply the plan
.\scripts\windows\Invoke-Renovate.ps1 -Managers pub        # narrow the managers
.\scripts\windows\Invoke-Renovate.ps1 -Recurse             # owned submodules, in place
```

`-Recurse` writes into the vendored submodules in place: commit and push each, then move the
gitlinks in every superproject that vendors it. The runner, its Node and token, and how
`--apply` writes what Renovate only detects: [`docs/source/project-operations.md`](docs/source/project-operations.md) § *Dependency upgrades, in detail*.

## 6. Docs owned by this repo

- Guides live in `docs/source/` as plain Markdown, published through exactly one
  builder: `scripts/linux/generate-docs.sh`, whose `DARTDOC_BUILD_GUIDES` array
  is the list of pages. There is no Sphinx site — the `sphinx-quickstart`
  scaffolding was deleted on 2026-09-15, unused by every lane
  ([`docs/source/project-operations.md`](docs/source/project-operations.md)
  § *There is no Sphinx site here*).
- [`docs/source/platforms.md`](docs/source/platforms.md) holds the full
  symptom→cause→fix table for containerized Windows builds.
- Update docs in the same PR as user-facing behaviour changes.
