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

**Rust-owned webcam inference (Windows today, Linux in progress).** The Stream
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

**Linux has this too as of 2026-09-16 — built, not yet seen working.** All four
links are in the tree: the `knt_push_frame`/`knt_api_version` C ABI exported
from the Linux plugin, `KATAGLYPHIS_RUST_FEATURES` forwarding, ONNX Runtime
bundling, and a Dart branch that routes Linux to `RustWebcamView` behind a
runtime `listCameras()` probe — so a build with no features set keeps the C++
GStreamer MethodChannel path unchanged. **This is an addition, not a
replacement**: the two paragraphs below stay true.

What is NOT done: **no frame has travelled Rust → `knt_push_frame` → texture.**
The ABI is verified only by `scripts/linux/check-knt-abi.sh`, which dlopens the
built plugin and checks the symbols and error codes; a real frame needs a Linux
desktop session and a camera. No lane sets `KATAGLYPHIS_RUST_FEATURES` either,
so CI still only ever builds the featureless Linux app. BACKLOG.md tracks both,
and the packaging gap under them.

**Linux/web cat detection stream.** The same Stream page consumes a WebRTC
stream produced by `third_party/OxidANT/crates/cat_webrtc`
(`kataglyphis_cat_webrtc`): V4L2/libcamera → ONNX (cat = COCO class 15) → boxes
burned into the RGBA frames → `webrtcsink` with its own signalling server.
`scripts/linux/cat-stream/serve.sh` puts HTTPS + COOP/COEP + a `/webrtc-ws`
proxy in front of it, so one build works on localhost, a LAN IP or a
Raspberry Pi; on a Pi 5 CSI camera the producer half is **OxidANT's**
`third_party/OxidANT/scripts/linux/cat-stream/run-producer-pi.sh`, a Pi Zero
2 W runs the image with the same host-libcamera swap plus a `gst-launch` no-AI
pipeline (the Rust producer does not fit 512 MB), and a RISC-V SoC runs the
riscv64 variant natively with a USB webcam (`--v4l2`) — see § 2's glue list.
Runbook: README § *Live cat detection stream*.

**`cat_webrtc` is this app's only WebRTC producer.** AccelerANTgine carries a
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
| The winamd64 image, Stevedore setup, `--isolation process`, the entrypoint vs `docker exec`, `docker commit` needing hyperv, the `wcifs` ENOENT class | `docs/windows-builds.md` |
| Bind mount vs tar-pipe, **Dev Drive filter setup**, container reuse, measured timings | `docs/windows-container-build-performance.md` |
| sccache's C++20-module blindness (clean + `SCCACHE_RECACHE=1` after a module-flag change) | `docs/windows-builds.md` |
| The image's pkg-config and rustup provisioning | `AGENTS.md` + `docs/windows-builds.md` |
| Wiring this repo to ANTfrastructure — resolver, actions, libraries | `docs/adopting-in-a-new-project.md` |
| Linux container builds | `docs/linux-build-basics.md` |
| Running the Linux lane locally on Windows (Rancher Desktop/nerdctl), and **a bind mount that resolves but is empty** — containerd's mount namespace, Windows vs WSL path form | [`docs/rancher-desktop-linux-containers.md` § *An empty mount is not a missing drive*](third_party/ANTfrastructure/docs/rancher-desktop-linux-containers.md#an-empty-mount-is-not-a-missing-drive) |
| The five shell-safety bug classes | `third_party/ANTfrastructure/AGENTS.md` § *Shell safety conventions* |
| appimagetool provisioning — pinned version + SHA256, not the moving `continuous` tag | `linux/scripts/02-toolchain/packaging-deps.sh`, subcommand `appimagetool` |
| Python venv + `uv` provisioning (installer downloaded to a file and SHA-checkable, never `curl \| sh`) | `linux/scripts/01-core/python_uv.sh` |
| The Dart gate for Linux lanes — deps, format, analyze, test, `--strict`/`--extra-package` | `linux/scripts/05-frameworks/flutter/flutter_checks.sh` |
| The CMake gate's machinery — `code_quality_find_cmake_files` + `CODE_QUALITY_CMAKE_EXCLUDE_PATHS` on Linux, `Initialize-UvVenvPython` on Windows | `linux/scripts/lib/code-quality.sh`, `windows/scripts/modules/WindowsFormatting.Common.psm1` |
| The canonical `.cmake-format.yaml` this repo's root copy syncs from, and the drift check | `shared/config/README.md` |
| Dependency upgrades — Renovate as a local CLI, why `--platform=local` only detects, the pinned Node/Renovate bootstrap, why `--apply` refuses a branchless submodule | `docs/dependency-updates.md` |

Two upstream facts repeated here only because they bite before you reach a doc:

- Every ANTfrastructure PowerShell module declares `#requires -Version 7.0`, so
  `Build-Windows.ps1` and `Start-Windows.ps1` do too — launch with `pwsh`, never
  `powershell`. Under 5.1 it fails as an opaque `Import-Module` error.
- Composite actions resolve at `@main`, so a ANTfrastructure change a workflow
  depends on must be pushed **before** the consumer change.

**This repo's glue** (deliberately thin):

- `scripts/windows/Resolve-BuildModule.ps1` — the one file that cannot live
  upstream, because it is what *finds* the submodule. `Import-BuildModule <Name>`
  checks ANTfrastructure first, then `scripts/windows/modules/`, which holds only
  genuinely project-specific modules (today: `WindowsPaths.Common`, encoding this
  repo's Flutter `build/windows/x64/{runner,plugins}` layout).
- `scripts/linux/lib/antfrastructure.sh` — the bash twin: `antfrastructure_source`
  and `antfrastructure_path`, resolved from `${BASH_SOURCE[0]}` so they work from
  any working directory.
- `scripts/agentic-loop/` — the adopted planner/executor loop: config, both
  runner wrappers, prompt overlays. Engine `opencode`, executor
  `opencode-go/deepseek-v4.1-flash`. Its Windows build/test driver is
  `scripts/windows/Build-Windows-Container.ps1`. Rules and commands: § 5.
- `scripts/linux/cat-stream/serve.sh` — serves the web build over TLS with the
  Stream page's COOP/COEP headers and proxies `/webrtc-ws` to the cat producer.
  No container involved; it is the deployment half of the demo.
  `--producer-host`/`--producer-port` front a producer on another board and
  `--state-dir` keeps concurrent instances apart.
- `third_party/OxidANT/scripts/linux/cat-stream/run-producer-pi.sh` — **not in
  this repo.** It moved to OxidANT under decision D12, which owns the
  `cat_webrtc` crate it builds and starts; this repo keeps the pointer, not a
  copy. It runs the cat producer from the image against a Pi 5 CSI camera
  (`--libcamera`), bind-mounting the host's Raspberry Pi OS libcamera stack
  ahead of the image's outdated upstream copy (the kernel 6.18 `rp1-cfe`
  entity rename + libpisp 1.7). `--build` builds the producer first;
  `--libs-only` refreshes the cached library closure. `serve.sh` above is the
  half that stays here, because the Flutter web build is this repo's.
- `scripts/linux/cat-stream/package-producer-bundle.sh` — container-less
  fallback for boards that cannot run the image comfortably (Pi Zero 2 W):
  exports the producer, a pruned GStreamer subset, the image's glibc (invoked
  through the bundled loader) and the library closure into
  `build/cat-stream/pi-bundle/` (~180 MB, aarch64). The target only needs
  libcamera installed; `--deploy HOST` rsyncs it there.

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
(the inference core the Windows plugin links) and
[`third_party/ANThology`](third_party/ANThology) (the shared Dart package).
`git submodule update --checkout --recursive` restores them. If a drifted
checkout is what you actually want, move the gitlink **and** fix the fallout in
the same change — a working tree that has quietly walked forward from its
gitlink is compiling something other than what is committed, and `git submodule
status` marks that only with a `+`.

Drift is guarded by ANTfrastructure's shared Pester suite, run from
[`.github/workflows/submodule-pins.yml`](.github/workflows/submodule-pins.yml)
after any pin bump. It checks both directions: each checkout sits at the
recorded commit, and the recorded commit is reachable from that submodule's
remote — a gitlink bumped to a commit that was never pushed builds on the
machine that made it and on no other.

**Submodule URLs are `https://github.com/Kataglyphis/<repo>.git`, all four.**
Not `git@github.com:`. An ssh remote needs a key, and none of the places that
have to resolve these has one: a CI runner, the `:latest-cross` container the
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

- **Six image gaps this repo used to work around are fixed in the image
  (2026-09-05); do not reintroduce the workarounds.** They were: a root-owned
  `.dart_tool` inside a read-only overlay layer, a populated `/opt/android-sdk`
  with neither `ANDROID_HOME` nor `ANDROID_SDK_ROOT` exported, `SCCACHE_DIR` and
  `CCACHE_DIR` pointing into the mounted checkout, root-owned `RUSTUP_HOME` and
  `CARGO_HOME` against a uid-1001 container, a single-platform `:latest-cross`
  tag, and no Java SDK. If one reappears it is an image regression, not
  something to patch around again — every symptom, and why each obvious local
  fix did not work, is kept in
  [`docs/source/platforms.md`](docs/source/platforms.md)
  § *Image gaps and image-tag history*. What remains on this side is
  `setup_compiler_cache`, which now only calls ANTfrastructure's `setup_sccache`:
  it points `RUSTC_WRAPPER` and both CMake compiler launchers at the **guarded**
  `sccache-launcher.sh`, which survives sccache's own fatal errors when a CMake
  `TryCompile` deletes the scratch directory under it.

- **The Android GStreamer SDK is in the image but unannounced.** It sits at
  `/opt/android/gstreamer` as a flat prefix (`gst-android/ndk-build`,
  `include/`, `lib/`), yet `GSTREAMER_ROOT_ANDROID` is not in the image ENV, so
  the native plugin's `CMakeLists.txt` stops the Android lane at configure time
  with `GSTREAMER_ROOT_ANDROID must be set`. The plugin accepts both the
  per-ABI and the flat layout, so the path alone is enough.
  `export_android_gstreamer_env` (`scripts/linux/lib/container-steps.sh`)
  probes and exports it, and returns untouched when the variable is already
  set — so it becomes a no-op the moment the image exports it, **which is the
  real fix.**

- **Every Android SDK component must be pinned to what the image ships.**
  `/opt/android-sdk` is read-only, so any component the Android Gradle Plugin
  asks for and does not find cannot be installed — Gradle stops with
  `The SDK directory is not writable`, one component per run. AGP's defaults
  (build-tools 35.x, NDK 27/28.x, cmake 3.22.1) are all
  wrong for this image, which carries 36.0.0, 29.0.14206865 and 4.1.2. Four
  places pin them and must agree: the global `subprojects` override in
  `android/build.gradle.kts` (which also drags third-party plugins such as
  permission_handler up from their own `compileSdk 35`), plus `android/app`,
  the native plugin's `android/`, and `rust_builder/android/`. The override
  block has to sit **above** the `evaluationDependsOn(":app")` block —
  that one forces evaluation, and registering `afterEvaluate` afterwards throws
  `Cannot run Project.afterEvaluate(Action) when the project is already
  evaluated`. BACKLOG.md tracks collapsing these to one source of truth.

- **`--gcc-toolchain` is load-bearing here, and ANTfrastructure deleted the helper
  that set it.** `export_clang_gcc_toolchain_env` went away upstream on
  2026-09-05 as dead code — true of ANTfrastructure, false of this repo, whose
  `export_toolchain_env` set exactly the bare `CC=clang` that needs it. Without
  the flag clang resolves libstdc++ against the system copy instead of the
  source-built GCC 16.2.0 and the link dies; with it the bundle and all four
  packages build. `export_toolchain_env` restores the flags through
  `gcc_toolchain_prefix()` — do not hard-code `/opt/gcc-16.2.0`. Upstream names
  `/usr/local/bin/clang-<arch>` as the replacement and `:latest-cross` ships
  none of them, so that branch is preferred and never taken. The two-run
  comparison, and the wider lesson for every hub bump, are in
  [`docs/source/platforms.md`](docs/source/platforms.md)
  § *Android and cross-toolchain constraints*.

- **Editing a lane script while its container runs makes the log lie.** bash
  sources `container-steps.sh` once at start, so a later edit does not take
  effect — but the log then shows behaviour that no longer matches the file on
  disk, and the next reader (including you, ten minutes on) draws the wrong
  conclusion. This cost one run: the log said "falling back to bare clang" while
  the file already had the fix. Wait for the container to exit.

- **Rust `i64` is `int` natively and `BigInt` on web, so only the web lane
  catches the mismatch.** flutter_rust_bridge maps it to `PlatformInt64`, a
  typedef that resolves per platform, and app code that passes a plain `int`
  compiles everywhere except web:
  `Error: The argument type 'int' can't be assigned to the parameter type
  'BigInt'` — from `rust_webcam_view.dart`, in a widget whose own doc comment
  calls it the Windows view. Wrap the value in `PlatformInt64Util.from(...)`,
  which is the identity on native. It lives in
  `package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart`, not in
  the public `flutter_rust_bridge.dart`, and importing the generated binding
  does not bring it along — Dart does not re-export transitively.

- **The web lane needs the nightly toolchain's `rust-src`.**
  `flutter_rust_bridge_codegen build-web` runs `wasm-pack … -Z
  build-std=std,panic_abort`, so cargo compiles the standard library itself and
  stops without the component:
  `".../nightly-x86_64-unknown-linux-gnu/lib/rustlib/src/rust/library/Cargo.lock"
  does not exist, unable to build with the standard library`. The two `rustup`
  lines that fix it sat commented out in `ci-container-run-web-linux.sh` — they
  were disabled back when `RUSTUP_HOME` was root-owned and every `rustup` write
  failed. That is fixed in the image, so they are live again; both are
  idempotent and become no-ops once the image ships `rust-src` and the
  `wasm32-unknown-unknown` target.

- **The web lane installs `flutter_rust_bridge_codegen` only when the image has
  none.** `:latest-cross` ships the binary at `FLUTTER_RUST_BRIDGE_VERSION`,
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

- **The Android prebuilts are aarch64 now, and the lane's toolchain moved with
  them.** Until 2026-09-11 the image carried `ELF x86-64` GStreamer/ONNX
  Runtime/OpenCV while the app builds `arm64-v8a`, so every archive died with
  `incompatible with aarch64linux`. The image ships only `arm64-v8a` now, so the
  cause is gone from the image — but **do not read that as "the lane links"**:
  the workflow has a single matrix row (x64), that row runs CodeQL, and CodeQL
  has been stopping the Gradle build at Kotlin compilation several steps before
  the native link. `abiFilters "arm64-v8a"` stays — real phones, not the
  emulator. AGP 9.4.0 + Gradle 9.7.1 builds that against four constraints, all
  load-bearing and none of them optional:

  - **Built-in Kotlin, with a declared KGP for the version check — and CodeQL
    has a ceiling under it.** `android.builtInKotlin=true`, no `kotlin-android`
    plugin anywhere, and `android/settings.gradle.kts` must keep
    `id("org.jetbrains.kotlin.android") version "2.4.20" apply false`: the
    declaration, not an application, is what raises the classpath KGP over
    Flutter's 2.2.20 floor (AGP bundles 2.2.10). Above that floor sits a ceiling
    belonging to a different tool — CodeQL's Java extractor refuses KGP 2.4.20
    and takes the whole Gradle build with it, so
    `scripts/linux/codeql/codeql-android.sh` builds the cluster for **cpp, c and
    rust only**. Do not "fix" the missing java rows by lowering the KGP: that
    trades a building app for a scan of five glue files. The observed run and
    both error messages are in that script's header comment and in
    [`docs/source/platforms.md`](docs/source/platforms.md)
    § *Android and cross-toolchain constraints*.
  - **`android.newDsl=false` stays.** The Flutter Gradle plugin still needs the
    legacy DSL types, which AGP 9.4 deprecates and Gradle 9.7's Kotlin-DSL
    compilation turns into `Script compilation errors` — hence the
    `@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")` at the top of
    `android/app/build.gradle.kts`.
  - **Cargokit carries a Gradle 9 port.** `Project.exec` and `Project.buildDir`
    are gone in Gradle 9; `rust_builder/cargokit/gradle/plugin.gradle` injects
    `ExecOperations` and reads `project.layout.buildDirectory`. Upstream Cargokit
    still has the old calls, so keep this patch when bumping the vendored copy.
  - **`permission_handler_android` is pinned to 13.0.1** in
    `pubspec_overrides.yaml`. The 14.x that permission_handler 13.0.2 resolves
    needs `compileSdk 37`; the image ships android-36 and its SDK is read-only.
    Drop the pin when the image carries 37.

- **The Rust manifest path must be counted from the *resolved* plugin dir.**
  Cargokit builds `CARGOKIT_MANIFEST_DIR` by string-joining
  `${CMAKE_CURRENT_SOURCE_DIR}/${manifest_dir}`, and for a Flutter plugin that
  directory is the ephemeral symlink
  `linux/flutter/ephemeral/.plugin_symlinks/oxidant`
  — six levels deep, pointing at `rust_builder/`, which is two. The kernel
  resolves the symlink *before* applying the `..`, so a chain counted from the
  symlink overshoots to `/` and Dart reports
  `PathNotFoundException: … /third_party/OxidANT/Cargo.toml`.
  `rust_builder/linux/CMakeLists.txt` therefore takes `REALPATH` of
  `CMAKE_CURRENT_SOURCE_DIR` first, which yields `../..` and survives the
  resolution. Verified against a rebuilt directory tree: six `..` fails, two
  succeed.
  `rust_builder/windows/CMakeLists.txt` still has the original construct and is
  deliberately left alone — that lane is green, and it has its own
  `Fix Plugin Symlinks (Junctions)` build step. Do not "unify" the two without
  a full Windows container build to prove it.

- **Never `dart format .` here.** It ignores `analysis_options.yaml` entirely,
  so the recursive walk reaches `flutter/`, `third_party/` and `build/` — one
  run reported `Formatted 7404 files (627 changed)` and rewrote the Flutter SDK
  on disk on the way. Both lanes list tracked files instead
  (`code_quality_find_dart_files` on Linux, `Get-ProjectDartFiles` on Windows;
  the same 60 files). Keep the tracked-file listing even though the SDK now
  comes from the image. `dart analyze` is *not* affected and never was. Detail:
  [`docs/source/project-operations.md`](docs/source/project-operations.md)
  § *Static checks*.

- **A single-arch image tag looks exactly like broken code.** `:latest-cross`
  was an amd64-only tag until 2026-09-04, so the arm64 matrix row ran x86-64
  binaries (`rustc: 1: ELF: not found`) and nothing in this repo could work
  around it. The tag is a proper OCI index now. Two habits survive the hunt:
  `fail-fast: false` stays on the matrix, and a `Failed to pull` line in a log
  is usually GitHub **echoing the retry script's source**, not running it.
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
- **Each preset installs into its own directory** —
  `build\windows\x64\runner\<preset>\` (and `plugins\<preset>\`), because
  `Build-Windows.ps1` calls `Resolve-KataglyphisWindowsLayout -Configuration
  $currentPreset` once per preset inside the `foreach ($currentPreset in
  $presetsToRun)` loop and passes the `$currentBuildDirFull` it returns
  (`$layout.RunnerDir`) as `-DCMAKE_INSTALL_PREFIX` on both configure paths, the
  `--preset` one and the generator one. Grep those names rather than line
  numbers: the refs that stood here (367/399/408) had already rotted to
  413/445/454. `x64-ClangCL-Windows-Release` is only the fallback
  used when no preset is named (`Get-WindowsBuildConfig.ps1`'s `CMakeConfiguration`).
  Presets no longer clobber each other — but `Start-Windows.ps1` must then be
  given the same preset name.
- **Running on an unprovisioned host** (`STATUS_DLL_NOT_FOUND`): stage the
  image's runtime DLLs into the runner (`C:\runtime\bin` + onnxruntime/DirectML →
  `runner\bin\`; `C:\runtime\lib\gstreamer-1.0` → `runner\lib\gstreamer-1.0\`).
  Two extra gotchas: `AccelerANTgine.dll` is built into a `bin\`
  **subdirectory** but the native plugin needs it **next to the exe**, and the
  VC++ redist CRT DLLs are not bundled. A healthy launch is ~130 MB with a real
  window; a ~6 MB process that exits means a missing dependency DLL. Full
  symptom table in [`docs/source/platforms.md`](docs/source/platforms.md).
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
  toolchain-less rustup shims are harmful.
- **Vendored ANTLR** (pulled in unconditionally by newer FUZZTEST) needs
  `WITH_STATIC_CRT OFF`, `ANTLR_BUILD_CPP_TESTS OFF`, `ANTLR_BUILD_SHARED OFF`,
  `/FIchrono`, and `LICENSE.txt` staged at the build root — its install rule
  assumes a monorepo layout. Wired up in
  `third_party/AccelerANTgine/third_party/CMakeLists.txt` — the inference core's
  own dependency list, not the plugin's.
- **The web Stream page needs a trustworthy origin, and the phone needs TLS in
  a proxy.** Chromium grants cross-origin isolation (COOP/COEP →
  `SharedArrayBuffer`, which the page checks) only on HTTPS or localhost, so a
  phone on the LAN gets no stream over plain HTTP. The GStreamer signalling
  server cannot end TLS for this repo's certificates — rustls rejects a
  self-signed one with `CaUsedAsEndEntity` — so
  `scripts/linux/cat-stream/serve.sh` serves the build and terminates TLS
  (port 8444) while proxying `/webrtc-ws` to the producer's plain `ws://`
  server (port 8443). The producer's `--cert/--key` exist; the proxy is the
  supported path.
- **`signalingServerUrl` may be host-relative, and only web resolves it.** A
  value starting with `/` (the committed `/webrtc-ws`) becomes
  `wss://<page-host>/webrtc-ws` in `WebRTCSettings.fromJsonFile`
  (`lib/settings/webrtc_settings.dart`); absolute `ws(s)://` URLs pass through
  untouched, as does everything on native, where the value is unused
  (`WebRTCView` is web-only).
- **A Pi Zero 2 W runs the image, but only with the host libcamera stack.**
  The image's upstream libcamera cannot drive the Zero's imx708 via `rpi/vc4`
  either: its isolated IPA process worker dies on start (`Failed to call
  start: -110`, then the socket is unreachable), while the host's rpt build
  uses the threaded proxy and works. The Zero also cannot build or run the
  Rust producer comfortably (512 MB), so the bring-up is the container +
  hostlibs mount + a `gst-launch` pipeline, exactly like the Pi 5's swap. Two
  traps: the image's `entrypoint.sh` sources `libcamera-env.sh`, which
  re-prepends `/opt/libcamera/lib` and silently overrides any
  `LD_LIBRARY_PATH` handed to `nerdctl run` (bypass it with `--entrypoint` —
  the Pi 5 runner does the same by exec'ing the binary directly); and
  gst-launch's `webrtcsink` `meta` must be a space-free structure
  (`meta="meta,name=Zero-Cat-Cam"`; a name with spaces fails to parse). The
  same swap carries any unicam/VC4 Pi (a Pi 4 runs the Rust producer with
  inference that way); there the `/dev/dma_heap/*` nodes need the camera
  ACLs too (`Could not open any dma-buf provider`, registration `-12`) and
  `/opt/gcc-16.2.0/lib64` must be on `LD_LIBRARY_PATH` for the image's ONNX
  Runtime (`GLIBCXX_3.4.36 not found` otherwise).
- **A RISC-V board runs the same image, but the host has opinions.** The
  SpacemiT X100 runs the riscv64 variant of `:latest-cross` natively (the
  producer builds in the container in minutes); a USB webcam needs `--v4l2`,
  an ACL on the camera node (it is `root:video 660` and the user is normally
  not in `video`) and UFW rules for `8443/tcp` plus the WebRTC UDP range
  (`32768:60999/udp`). `serve.sh --producer-host` must be given the board's
  **IP, not its mDNS name**: nginx resolves `proxy_pass` hostnames once at
  startup, so a DHCP or mDNS address change leaves it answering `101` while
  nothing ever reaches the producer. Each `serve.sh` instance also needs its
  own port opened on the **dev host** — a second board's page stays
  unreachable while the first board's still works, which reads like a
  producer fault but is a missing `ufw allow 8446/tcp`.
- **The frb Dart bindings must match the Rust runtime's frb version.** They
  were stale at 2.12.0 against 2.13.0 and the web build died with an empty
  `Uncaught` before `pkg/oxidant.js` loaded. Regenerate both sides together:
  `flutter_rust_bridge_codegen generate` writes `lib/src/rust/` **and**
  OxidANT's `src/frb_generated.rs`; when the wasm artefacts are involved,
  `flutter_rust_bridge_codegen build-web --release --rust-root
  third_party/OxidANT`. `web/pkg/` is generated and gitignored.
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

**Both lanes run the same thing locally and in CI. Reproduce locally first —
CI is not a debugger.**

**Run one lane at a time.** Every local lane bind-mounts the *same* checkout,
and the generated files at its root are per-host, not per-lane
(`android/local.properties`, the ephemeral plugin symlinks, `.dart_tool`, the
iOS/macOS `Generated.*`). Two lanes running together overwrite each other
mid-build and the failure names neither of them — a Windows container run
beside a Linux Android run left `flutter.sdk=C:\ProgramData\...` next to
`sdk.dir=/opt/android-sdk`, and Gradle stopped on a path that was both. CI never
sees this: each lane is its own runner with its own clone.

Windows builds run containerized, and **CI runs the exact same script** — the
workflow [`dart_on_native_windows.yml`](.github/workflows/dart_on_native_windows.yml)
calls `Build-Windows.ps1` through ANTfrastructure's `run-in-windows-container`
action, so "works locally" and "works in CI" are the same steps by construction.
Locally:

```powershell
& "$env:ProgramFiles\Stevedore\bin\docker.exe" run --rm --isolation process `
  --mount "type=bind,source=$PWD,target=C:\ws-mnt" -w C:\ws-mnt `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64 `
  pwsh -NoProfile -ExecutionPolicy Bypass -File C:\ws-mnt\scripts\windows\Build-Windows.ps1 `
    -SkipMsixPackaging
```

`-SkipMsixPackaging` alone is exactly what the workflow passes; adding
`-Configurations` is a deliberate deviation, not the parity run. **Run it in the
container, not on the host** — the Windows engine is Stevedore's, not Rancher
Desktop's, whose `docker`/`nerdctl` shims are first on `PATH`, and the host's
`cmake` is Strawberry Perl's 3.29.2, too old for
`cmake_minimum_required(VERSION 3.31.6)`. The 2026-09-06 parity run, what it
produced and which stale pre-rename artifacts sit beside it:
[`docs/source/platforms.md`](docs/source/platforms.md) § *Windows build-step
traps and MSIX packaging*.

**The mount target must not already exist in the image.** `target=C:\workspace`
fails at container creation with `hcs::CreateComputeSystem ... The request is not
supported` on hosts whose Docker/hcsshim is version-skewed from the image —
`C:\workspace` is a baked image dir. Use a fresh target (`C:\ws-mnt` above; CI
mounts `D:\ws → C:\ws`). ANTfrastructure owns the why — see § 2.

Four quality/output steps run before the native build (`-CodeQL` short-circuits
before them), each skippable with the paired switch: **Dart format + CMake
format** (`-SkipFormat`), **Dart analyze + Flutter tests** (`-SkipTests`),
**API docs generation** (`-SkipDocs`).

**A failed step does not abort the run.** None of them is declared `-Critical`,
and `-StopOnError` is off by default, so the step is recorded and the build
carries on — the log still ends with `=== Build Complete ===` even when
something failed, and the script only exits 1 from its `finally` block. A real
run shows both lines together (`FAILED: MSIX Packaging` … `=== Build Complete ===`).
**Trust the process exit code and `failedSteps` in `logs/build-summary-*.json`,
never the log tail.**

Two Windows-specific traps these steps carry: the format gate lists
`lib test integration_test test_driver` rather than `.` (the recursive walk
reaches the vendored submodule gitdir and exceeds MAX_PATH), and docs generation
runs a `pub global activate dartdoc` (≥ 9.0.9) instead of the SDK-bundled
`dart doc`, whose 9.0.4 crashes on any Flutter app. Both:
[`docs/source/platforms.md`](docs/source/platforms.md) § *Windows build-step
traps and MSIX packaging*.

- Preset aliases: `clangcl-{debug,profile,release}`, `msvc-{debug,release}`,
  `clang-{debug,profile,release}` → `x64-ClangCL-Windows-Debug` etc.
- Switches: `-SkipTests`, `-SkipFormat`, `-SkipDocs`, `-CleanBuild`, `-SkipMsixPackaging`,
  `-SkipBootstrapFlutterBuild`, `-ContinueOnError`/`-StopOnError`, `-CodeQL`. The
  closing **Delivery Check** cannot be skipped.
- Logs land in `logs/` (`build-windows-*.log` + `build-summary-*.json`); API
  docs in `doc/api` (git-ignored).

**The agentic loop (adopted 2026-09-13).** `scripts/agentic-loop/` holds the
config, both runner wrappers and the project prompt overlays. Engine `opencode`,
executor `opencode-go/deepseek-v4.1-flash`, planner `opencode-go/glm-5.2`. It
runs on the host and builds through `scripts/windows/Build-Windows-Container.ps1`,
which drives `Build-Windows.ps1` in a **reused** Stevedore container (tar-pipe
transport, `WindowsContainerBuild.Reuse`, so Cargo/sccache/pub caches survive)
and always skips docs and MSIX. Tests are `-TestsOnly` — the Dart gates in the
same container. The config contract and build-matrix semantics are owned by
[`third_party/ANTfrastructure/docs/windows-agentic-loop.md`](third_party/ANTfrastructure/docs/windows-agentic-loop.md);
`.opencode/agents/` is generated and gitignored — edit the overlays, never it.

```powershell
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1            # planner + executor
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1 -DryRun    # wiring check
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1 -PlannerOnly
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1 -ExecutorOnly
```

The loop does not watch CI and auto-commits with `git add -A`; do not run
interactive work in the same tree without checking whether it is live. The loop
itself is ANTfrastructure's —
[`docs/adopting-in-a-new-project.md` § 4](third_party/ANTfrastructure/docs/adopting-in-a-new-project.md#4-the-agentic-loop).

**MSIX packaging.** `msix_config.build_windows` is `false` on purpose — this
script owns the build — and the **MSIX Compatibility Layout** step copies the
preset's output into the flat `runner\Release\` directory that msix looks for.
CI passes `-SkipMsixPackaging`, so packaging is exercised only locally, which is
how both halves stayed broken unnoticed until 2026-09-03:
[`docs/source/platforms.md`](docs/source/platforms.md) § *Windows build-step
traps and MSIX packaging*.

**The CI lane** ([`dart_on_native_windows.yml`](.github/workflows/dart_on_native_windows.yml))
is four ANTfrastructure actions and nothing hand-rolled:
`prepare-windows-container-host`, `run-in-windows-container`,
`actions/upload-artifact` and `upload-codeql-sarif`. Three consequences, each
easy to undo by accident:

- It prunes `third_party/DocumANTation` from the recursive checkout. Without
  that, the nested `.git/modules/<name>/` chain makes git abort with
  `fatal: '$GIT_DIR' too big` — git's own limit, not MAX_PATH, so no clone root
  is short enough.
- `mount-source`/`mount-target` stay unset, because the action already defaults
  to `D:\ws` → `C:\ws`, which is where the short-path clone put the tree.
- Artifact paths are therefore **absolute under the short-path clone**
  (`steps.prep.outputs.workspace`), never relative to `github.workspace`.

The measurements behind all three — the gitdir-length table, the two directory
renames that fixed it, and why a local checkout is the worst case — are in
[`docs/source/platforms.md`](docs/source/platforms.md) § *The Windows CI lane
and the `$GIT_DIR` limit*.

CI passes `-SkipMsixPackaging`, and `-CodeQL` is off there because of runtimes.

### The Dart gate in 23 seconds, without a lane

**There is no Flutter or Dart SDK on the Windows dev box** — `flutter` is not on
`PATH` and there is no host SDK to put there. That makes it look as though the
smallest unit of feedback is a whole container lane. It is not: the image
carries the SDK at `/opt/flutter`, and running *only* the Dart gate against a
bind-mounted checkout costs **23 s warm** (measured 2026-09-16; 214 s the first
time, which is `flutter pub get` populating the cache volume).

```powershell
# once: the cache volume must belong to the container's uid, like every other
# volume this repo mounts — see Invoke-LinuxLane.ps1's chown step.
nerdctl run --rm --platform linux/amd64 `
  --mount "type=volume,source=oa-fastloop-pub,target=/vol" alpine chown -R 1001:1001 /vol

# then, per edit:
nerdctl run --rm --platform linux/amd64 `
  -v "C:\GitHub\OmniAccelerANT:/workspace" -w /workspace `
  --mount "type=volume,source=oa-fastloop-pub,target=/pubcache" -e PUB_CACHE=/pubcache `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest-cross `
  bash -lc 'export PATH=/opt/flutter/bin:$PATH; git config --global --add safe.directory "*"; flutter test'
```

Swap `flutter test` for `flutter analyze` (~164 s — it analyses the whole
workspace) or for both. `PUB_CACHE` on a named volume is what makes the second
run cheap, and it is also the rule from § 5: write-heavy paths stay off the host
mount.

**This is not a substitute for the lane.** It runs the Dart gate and nothing
else — no `dart format` file listing, no CMake gate, no build, no packaging, and
it never touches the C++ or Rust. Use it to iterate; use `Invoke-LinuxLane.ps1`
to believe the result. It is also why "add a test" is a cheap proposal in this
repo and not an expensive one.

### The Linux lane, locally

`scripts/windows/Invoke-LinuxLane.ps1` starts the same image and runs the same script
with the same arguments as that lane's workflow. `-Lane` selects which:

| `-Lane` | script | workflow |
| --- | --- | --- |
| `native` (default) | `ci-container-run-native-linux.sh` | [`dart_on_native_linux.yml`](.github/workflows/dart_on_native_linux.yml) |
| `android` | `ci-container-run-android.sh` | [`dart_build_android_app.yml`](.github/workflows/dart_build_android_app.yml) |
| `web` | `ci-container-run-web-linux.sh` | [`dart_on_web_linux.yml`](.github/workflows/dart_on_web_linux.yml) |

Each entry mirrors its workflow's `extra-args` and `script`, so change the pair
together. The argument sets are meant to match exactly — the android lane also
matches in *not* passing `--privileged`.

```powershell
.\scripts\windows\Invoke-LinuxLane.ps1 -SkipDocs                        # native, x64
.\scripts\windows\Invoke-LinuxLane.ps1 -Lane android -SkipCodeQL
.\scripts\windows\Invoke-LinuxLane.ps1 -Lane web
.\scripts\windows\Invoke-LinuxLane.ps1 -Arch arm64                      # needs QEMU, see below
```

**arm64 locally needs QEMU registered once per VM boot**, and an emulated
arm64 run produces tar and deb but never flatpak or AppImage: `qemu-user` does
not carry `unshare(CLONE_NEWUSER)` through for bubblewrap, and cannot load the
static-PIE `appimagetool`. Neither restriction touches CI, whose arm64 row runs
on a real `ubuntu-26.04-arm` runner. The `binfmt` registration commands, the
pull sizes, and both error messages verbatim:
[`docs/source/project-operations.md`](docs/source/project-operations.md)
§ *The Linux lane, locally*.

**Everything write-heavy must stay off the host mount.** A bind-mounted Windows
drive cannot do `utime`, `chmod` or `fchmod` for the container uid, and each of
those surfaces as a different, misleading error:

| What | Where it lives now | Symptom when it did not |
| --- | --- | --- |
| CMake/ninja build tree | named volume on `/workspace/build` | — |
| pub's download cache | named volume on `/workspace/.pub-cache` | `Rename failed, path = '/workspace/.pub-cache/_temp/…' (OS Error: Permission denied, errno = 13)`, then `Failed to update packages` — **but only on a run that downloads something.** A warm cache resolves from disk and renames nothing, so the local lane passed for as long as nobody edited `pubspec.yaml` |
| cargo's target tree | named volume on `/workspace/third_party/OxidANT/target` | `error: failed to build archive at '…/libwasm_bindgen_macro_support-*.rlib': failed to remove temporary directory: Permission denied (os error 13) at path '…/out/.tmpXXXXXX.temp-archive'`. Same class as the row above, one verb over: the mount refuses the **remove**, not the write. The web lane hits it hardest because `-Z build-std` recompiles the standard library |
| flatpak repo, build tree, builder state, manifest staging **and the finished bundle** | `/tmp/flatpak-work` | `fchmod: Operation not permitted`, first from the OSTree repo, later from `build-bundle` |
| ccache / sccache | `/var/cache/{ccache,sccache}`, set by the image | `Can't initialize ccache use: Failed to set permissions` |

Only the finished artifacts are written into `out/`. This is ANTfrastructure's
documented rule for build directories and caches, applied to the packaging
steps as well.

**The flatpak bundle is written under `/tmp/flatpak-work` and copied out**, and
the step asks `ostree --repo=<repo> refs` whether the app is committed rather
than trusting flatpak-builder's exit code. Both come out of one hunt —
`error: fchmod` after `Pruning cache`, which is not the prune — written up in
[`docs/source/project-operations.md`](docs/source/project-operations.md)
§ *The Linux lane, locally*. All four formats build locally on x64.

It drives Rancher Desktop's `nerdctl` (found on `PATH`, else under
`%ProgramFiles%`), because that is the local Linux engine on this box; CI uses
`docker` through ANTfrastructure's `run-in-linux-container`. Everything inside the
container is identical.

**`-v name:/path` is not a named volume on Windows nerdctl.** It silently binds
`$PWD/name`, so `Invoke-LinuxLane.ps1` always spells the mount
`--mount type=volume,source=…,target=…`, which nerdctl cannot reinterpret as a
path. CI is unaffected. The measurement that settled it, and the cosmetic
`flutter clean … Device or resource busy (errno 16)` that mounting `build/`
produces on every run, are in
[`docs/source/project-operations.md`](docs/source/project-operations.md)
§ *The Linux lane, locally*.

**Two traps, both of which produce a mount that resolves but is empty:** `D:`
must exist inside *containerd's own* mount namespace, which is not the distro's
and is gone after every VM restart — the fix is ANTfrastructure's
[`docs/rancher-desktop-linux-containers.md` § *An empty mount is not a missing drive*](third_party/ANTfrastructure/docs/rancher-desktop-linux-containers.md#an-empty-mount-is-not-a-missing-drive)
— and the path you pass must be the **Windows** one (`D:\…`), because nerdctl
translates it itself and handing it the already-translated `/mnt/d/…` binds
nothing. A `wsl: Failed to translate '<cwd>'` line in the output is noise, not a
failed mount.

No lane installs Flutter. ANTfrastructure's `flutter_lane_prepare_env`
([`05-frameworks/flutter/lane-prologue.sh`](third_party/ANTfrastructure/linux/scripts/05-frameworks/flutter/lane-prologue.sh))
checks that one exists at `--flutter-dir`, puts it on `PATH`, registers the
workspace `safe.directory`, points `PUB_CACHE` at `.pub-cache` and reports the
version it found; whatever the image carries is what gets used. A multi-GB
`flutter/` in the repo is a leftover from before that — git-ignored, and safe to
remove.

Run the app on the host once artifacts are back:

```powershell
# -Configuration is required: it names the runner\<preset>\ directory to launch.
.\scripts\windows\Start-Windows.ps1 -Configuration x64-ClangCL-Windows-Release
.\scripts\windows\Start-Windows.ps1 -Configuration x64-ClangCL-Windows-Debug
```

Linux builds run containerized. **CI does not use the stage script below.** Its
path is the ANTfrastructure composite action
`.github/actions/run-in-linux-container@main`, which runs
`scripts/linux/ci/ci-container-run-native-linux.sh` *inside* the container with
CLI flags, not env vars
([`dart_on_native_linux.yml`](.github/workflows/dart_on_native_linux.yml):60,70-78):

```bash
bash /workspace/scripts/linux/ci/ci-container-run-native-linux.sh \
  --arch x64 --build-mode release --flutter-dir /opt/flutter \
  --app-name omni-accelerant \
  --package-formats tar,deb,flatpak,appimage
```

`--flutter-dir` only says *where* to look; it defaults to `/opt/flutter`. There
is no `--install-flutter` and no `--flutter-version`.

**Flutter comes from the image, and this repo does not have an opinion about
which version.** `flutter_lane_prepare_env` returns non-zero if `--flutter-dir`
holds no `bin/flutter`, and otherwise prints the `flutter --version` this run
got and moves on. To change the Flutter version, change the image. Why the pin-and-install
machinery went, and what it was costing every Android run:
[`docs/source/project-operations.md`](docs/source/project-operations.md)
§ *The Linux lane, locally*.

The lane scripts take their inputs as CLI flags and exit 2 on a missing
required one rather than guessing — `--arch`, `--app-name` and (native only)
`--package-formats`. `--flutter-dir` defaults to `/opt/flutter`. The matrix
values CI passes are in
[`dart_on_native_linux.yml`](.github/workflows/dart_on_native_linux.yml).

**`--app-name` derives from `pubspec.yaml`; do not hard-code it again.**
`resolve_app_name` in `scripts/linux/lib/cli-common.sh` reads the `name:` entry
and swaps `_` for `-`, so `omni_accelerant` yields `omni-accelerant`.
`run-native-linux.sh`, `run-android.sh` (which appends `-apk`),
`package-linux.sh` and `Invoke-LinuxLane.ps1` all default through it. Before
2026-09-05 the literal sat in all four plus the workflows, seven copies that a
rename had to find. The workflows still pass the value explicitly, which is
what keeps CI independent of a host's `pwd`.

**CodeQL runs in the android lane and nowhere else.**
`scripts/linux/codeql/codeql-android.sh` installs the CLI, builds a
`--db-cluster` for **c, cpp and rust** around `flutter build apk` and runs two
`database analyze` suites — budget hours, not minutes. Java and Kotlin are
deliberately not in that cluster: CodeQL's Java extractor refuses this repo's
KGP and kills the Gradle build with it — § 4, the built-in-Kotlin bullet. The native lane
implements none and its driver *refuses* `--run-codeql true` with exit 2 rather
than reporting success over a scan that never happened;
`Invoke-LinuxLane.ps1` hard-codes `false` for it and for web. So `-SkipCodeQL`
changes nothing except under `-Lane android`, and the native `build` job (both
matrix rows) is the plain
`flutter clean && flutter pub get && flutter build linux --release`.

`FLUTTER_DIR` defaults to `/opt/flutter` — the image's SDK, shared by every
lane and never written to. It used to default inside the workspace, which made
an x64 and an arm64 run in the same tree overwrite each other's SDK; that is
gone along with the installer.

Quality gates — `Build-Windows.ps1` runs these by default (skip with
`-SkipFormat` / `-SkipTests` / `-SkipDocs`). Note the format command is **not**
`dart format .`: that is the form documented above as crashing on Windows.

```bash
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
cmake-format -c .cmake-format.yaml --check <the hand-maintained CMake files>
flutter analyze
flutter test
dart pub global run dartdoc --output doc/api
```

The Linux `checks` stage runs the same three (with `dart analyze` rather than
`flutter analyze`), and **whether a failure is fatal depends on the lane**, not
on the stage:

| Lane | `--strict-checks` | A failing format/analyze/test |
| --- | --- | --- |
| native Linux ([`dart_on_native_linux.yml`](.github/workflows/dart_on_native_linux.yml)) | `true` | reds the lane |
| web ([`dart_on_web_linux.yml`](.github/workflows/dart_on_web_linux.yml)) | `true` | reds the lane |
| android (`ci-container-run-android.sh`) | not passed | reports and moves on — deliberate |

So "treat a green `checks` run as *was executed*, not as *passed*" is true of
the **android** lane only. It was true of all three until fc8b65c turned
`--strict-checks true` on for native, and this paragraph went on claiming the
`|| true` behaviour for every lane long after that — while a paragraph eight
lines below said the opposite. The `|| warn` arm still exists; it moved upstream
into `flutter_checks.sh` and is what the android lane still takes.

`Invoke-LinuxLane.ps1` passes `-StrictChecks true` by default (since
2026-09-16) so a local run grades exactly as CI does. It defaulted to `false`
before that, which is the failure mode the driver exists to prevent: the lane
you run to reproduce CI was the more forgiving of the two.

The CMake gate NO LONGER follows that switch.
`run_cmake_format_check` takes no arguments at all now: it used to accept a
strictness flag and IGNORE its own verdict when that flag was false, so it errors
(exit 2) if handed one rather than letting a stale caller pass silently. It runs in
the native-Linux lane and the Android lane and is FATAL in both; the web lane builds
no native CMake code and does not run it.

That flip is safe for a measured reason, not an optimistic one — the gate's 13
files are already clean and the native-Linux lane has passed
`--strict-checks true` since fc8b65c, so the Android lane can only catch drift
that already blocks the merge elsewhere.

**The CMake format gate covers hand-maintained CMake only — 13 files today.**
Both lanes build the same list and exclude the same generated and vendored
trees. Do not widen the gate onto any of them: it would fight the generator or
upstream. The exclusion list, with what each one was verified to be, is in
[`docs/source/project-operations.md`](docs/source/project-operations.md)
§ *The CMake format gate*.

`.cmake-format.yaml` at the root is the consumer copy of ANTfrastructure's
canonical config — `shared/config/README.md` owns why it is a copy. Refresh it
with `pwsh -File third_party/ANTfrastructure/shared/config/Sync-SharedConfig.ps1
-RepoRoot . -Write` (or the `sync-shared-config.sh --repo-root . --write` form)
— **no `-Ignore`**: what this repo takes is declared in
[`.antfrastructure-shared.manifest`](.antfrastructure-shared.manifest), three
rows, and the scripts refuse `-Ignore` while that file exists. Where
cmake-format itself comes from, why there is no root `requirements.txt`, and why
`.gitattributes` pins CMake files to LF:
[`docs/source/project-operations.md`](docs/source/project-operations.md)
§ *The CMake format gate*.

### Dependency upgrades

**Submodule upgrades go through this, not by hand.** Nothing in
`.github/workflows/` runs it; it blocks no commit.

**Report-first (owner directive 2026-09-11): a run reports. `-Apply` only when the
owner explicitly asked for it in that turn.**

On this host, run it in the cross container:

```powershell
.\scripts\windows\Invoke-Renovate.ps1                      # what is behind
.\scripts\windows\Invoke-Renovate.ps1 -Apply -DryRun       # the plan
.\scripts\windows\Invoke-Renovate.ps1 -Apply               # apply the plan
.\scripts\windows\Invoke-Renovate.ps1 -Managers pub        # narrow the managers
.\scripts\windows\Invoke-Renovate.ps1 -Recurse             # owned submodules, in place
```

`scripts/linux/renovate-local.sh` remains the language-independent entry point
(every lane and Linux host calls it); the PowerShell runner only wires it to
`nerdctl`: it mounts the repo at `/workspace`, adds the `safe.directory`
entries the root-owned bind mount needs (`/workspace` and `/workspace/*` for the
submodule worktrees), and forwards `-Apply`/`-DryRun`/`-Refresh`/
`-Managers`/`-PrintBin`.

Two runner behaviours worth knowing before a run surprises you: the container
downloads its own checksum-pinned Node onto the `kataglyphis-renovate-cache`
volume, and the runner passes `gh`'s token as `GITHUB_COM_TOKEN`. What each is
for, and what goes wrong without it:
[`docs/source/project-operations.md`](docs/source/project-operations.md)
§ *Dependency upgrades, in detail*.

`-Recurse` runs ANTfrastructure's `renovate-fleet.sh --vendored`. The fleet
driver finds the repos BESIDE the superproject, dedups by remote identity and
orders them dependencies-first; `--vendored` then appends the vendored
checkouts of identities that have no own checkout, which inside this container
is all of them — the mount is one superproject and there is nothing beside it.
This repo carried its own 135-line submodule walker until 2026-09-15 because
the fleet driver refused to write in place at all; that refusal is now an
opt-in, and writing into a vendored worktree still means: after an `-Apply`,
commit and push each submodule, then move the gitlinks in every superproject
that vendors it.

Renovate is a local CLI and only **detects** — `--platform=local` cannot write
— so the `--apply` half is this repo's own code, and `--managers` narrows a run
rather than enabling it. The mechanics, including why `--apply` needs the git
that *wrote* the working tree:
[`docs/source/project-operations.md`](docs/source/project-operations.md)
§ *Dependency upgrades, in detail*.

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
