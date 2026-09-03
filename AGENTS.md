# AGENTS.md

Guidance for coding agents (and new contributors) working in
Kataglyphis-Inference-Engine.

Laid out per ContainerHub's
[`shared/templates/AGENTS.md.template`](ExternalLib/Kataglyphis-ContainerHub/shared/templates/README.md).
The rule that shapes it: *would this still be true in a different project?* If
yes, ContainerHub owns it and § 2 links to it. If no, it is written out in § 3.

## 1. What this project is

A Flutter/Dart app (`lib/`) targeting Windows, Linux, Android and web, with a
Rust core and a C++ inference plugin underneath it.

| Path | What lives there |
| --- | --- |
| `lib/` | The Flutter/Dart frontend |
| `ExternalLib/Kataglyphis-RustProjectTemplate` | Rust core, bridged via `flutter_rust_bridge` — regenerate bindings after Rust API changes with `flutter pub run flutter_rust_bridge_codegen` |
| `ExternalLib/Kataglyphis_NativeInferencePlugin` | C++ inference plugin (`native/KataglyphisCppInference`); links GStreamer + ONNX Runtime via CMake/pkg-config |
| `scripts/windows/`, `scripts/linux/` | Thin wrappers over ContainerHub drivers + this repo's own glue |
| `ExternalLib/Kataglyphis-ContainerHub` | The submodule owning every reusable script, module and doc |

**Windows webcam inference.** The Stream page runs a Rust-owned
webcam → ONNX → Flutter-texture pipeline: `crates/media` GStreamer capture →
`src/webcam_engine.rs` → frb `src/api/webcam.rs` stream. Frames reach the texture
through the native plugin's `knt_push_frame` C ABI; only detection metadata
crosses the bridge. Gated by the Rust features
`gstreamer,onnxruntime_dynamic,onnxruntime_directml`, enabled on Windows via the
`KATAGLYPHIS_RUST_FEATURES` env var (forwarded to cargo by `rust_builder`'s
CMake → Cargokit). `mfvideosrc` needs the `mediafoundation` GStreamer plugin
**and** a Windows client host; it falls back to `ksvideosrc`. Details in
[`docs/source/camera-streaming.md`](docs/source/camera-streaming.md)
§ *Windows: Rust-owned webcam inference*.

## 2. What ContainerHub owns — links only

**Do not restate these procedures here.** Start at
[`ExternalLib/Kataglyphis-ContainerHub/docs/INDEX.md`](ExternalLib/Kataglyphis-ContainerHub/docs/INDEX.md),
which maps topic → owning document, so these links survive upstream
reorganisation.

| Topic | Where |
| --- | --- |
| The winamd64 image, Stevedore setup, `--isolation process`, the entrypoint vs `docker exec`, `docker commit` needing hyperv, the `wcifs` ENOENT class | `docs/windows-builds.md` |
| Bind mount vs tar-pipe, **Dev Drive filter setup**, container reuse, measured timings | `docs/windows-container-build-performance.md` |
| sccache's C++20-module blindness (clean + `SCCACHE_RECACHE=1` after a module-flag change) | `docs/windows-builds.md` |
| The image's pkg-config and rustup provisioning | `AGENTS.md` + `docs/windows-builds.md` |
| Wiring this repo to ContainerHub — resolver, actions, libraries | `docs/adopting-in-a-new-project.md` |
| Linux container builds | `docs/linux-build-basics.md` |
| Running the Linux lane locally on Windows (Rancher Desktop/nerdctl), and **a bind mount that resolves but is empty** — containerd's mount namespace, Windows vs WSL path form | `docs/rancher-desktop-linux-containers.md` |
| The five shell-safety bug classes | ContainerHub `AGENTS.md` § *Shell safety conventions* |

Two upstream facts repeated here only because they bite before you reach a doc:

- Every ContainerHub PowerShell module declares `#requires -Version 7.0`, so
  `Build-Windows.ps1` and `Start-Windows.ps1` do too — launch with `pwsh`, never
  `powershell`. Under 5.1 it fails as an opaque `Import-Module` error.
- Composite actions resolve at `@main`, so a ContainerHub change a workflow
  depends on must be pushed **before** the consumer change.

**This repo's glue** (deliberately thin):

- `scripts/windows/Resolve-BuildModule.ps1` — the one file that cannot live
  upstream, because it is what *finds* the submodule. `Import-BuildModule <Name>`
  checks ContainerHub first, then `scripts/windows/modules/`, which holds only
  genuinely project-specific modules (today: `Windows.Paths`, encoding this
  repo's Flutter `build/windows/x64/{runner,plugins}` layout).
- `scripts/linux/lib/containerhub.sh` — the bash twin: `containerhub_source`
  and `containerhub_path`, resolved from `${BASH_SOURCE[0]}` so they work from
  any working directory.

## 3. Pitfalls specific to this project

Everything here is false or meaningless in another repo — that is why it is
written out rather than linked.

- **ASAN works, but only against Microsoft's runtime.** LLVM's
  `clang_rt.asan_dynamic` loads *after* ucrtbase, so allocations made during
  CRT/COM startup are unhooked and it aborts with an unsuppressible `bad-free`
  when combase/ole32 frees them. That is a property of a COM-hosting Flutter
  app, not of the image. Microsoft's runtime (`VC\Tools\MSVC\<ver>\bin\Hostx64\x64\clang_rt.asan_dynamic-x86_64.dll`)
  tracks Windows heap ownership and passes foreign frees through. The plugin's
  `cmake/Sanitizers.cmake` links Microsoft's thunk + import lib while keeping
  clang's instrumentation; `Start-Windows.ps1` stages the DLL next to the exe and
  sets `ASAN_OPTIONS=alloc_dealloc_mismatch=0:check_malloc_usable_size=0`.
  Build-time needs a dynamic CRT throughout (`-shared-libsan`, **no `/MT`
  overrides anywhere** — module BMIs re-emit `detect_mismatch` into importers, so
  one `/MT` BMI poisons everything).
- **The clangcl-Debug preset ships with ASAN ON** and builds + runs green (Dart
  VM up, camera live). Historic gotchas, all fixed: naive ASAN dragged `/MT`
  into Flutter's `/MD` objects (`lld-link` RuntimeLibrary mismatch), and
  `kataglyphis_libfuzzer.exe` hit an `annotate_string` mismatch vs
  `clang_rt.fuzzer`.
- **All presets install into the same directory** —
  `build\windows\x64\runner\x64-ClangCL-Windows-Release\` holds whichever preset
  built last. Copy artifacts away between preset runs.
- **Running on an unprovisioned host** (`STATUS_DLL_NOT_FOUND`): stage the
  image's runtime DLLs into the runner (`C:\runtime\bin` + onnxruntime/DirectML →
  `runner\bin\`; `C:\runtime\lib\gstreamer-1.0` → `runner\lib\gstreamer-1.0\`).
  Two extra gotchas: `KataglyphisCppInference.dll` is built into a `bin\`
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
  assumes a monorepo layout. Wired up in the plugin's
  `ExternalLib/CMakeLists.txt`.

## 4. Build, run, test

Windows builds run containerized, and **CI runs the exact same script** — the
workflow [`dart_on_native_windows.yml`](.github/workflows/dart_on_native_windows.yml)
calls `Build-Windows.ps1` through ContainerHub's `run-in-windows-container`
action, so "works locally" and "works in CI" are the same steps by construction.
Locally:

```powershell
& "$env:ProgramFiles\Stevedore\bin\docker.exe" run --rm --isolation process `
  --mount "type=bind,source=$PWD,target=C:\ws-mnt" -w C:\ws-mnt `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64 `
  pwsh -NoProfile -ExecutionPolicy Bypass -File C:\ws-mnt\scripts\windows\Build-Windows.ps1 `
    -Configurations "clangcl-release" -SkipMsixPackaging
```

**The mount target must not already exist in the image.** `target=C:\workspace`
fails at container creation with `hcs::CreateComputeSystem ... The request is not
supported` on hosts whose Docker/hcsshim is version-skewed from the image —
`C:\workspace` is a baked image dir. Use a fresh target (`C:\ws-mnt` above; CI
mounts `D:\ws → C:\ws`). ContainerHub owns the why — see § 2.

Three quality/output steps **always run before the native build**, each fatal,
each skippable with the paired switch: **Dart format** (`-SkipFormat`), **Dart
analyze + Flutter tests** (`-SkipTests`), **API docs generation** (`-SkipDocs`).
Two Windows-specific traps these steps carry:

- The format gate formats `lib test integration_test test_driver`, **not `.`**:
  `dart format .` recurses into `.git`, and the deeply nested vendored submodule
  gitdir exceeds Windows MAX_PATH, so the listing throws and the gate crashes
  before formatting anything.
- Docs generation does **not** use the SDK-bundled `dart doc`. The dartdoc 9.0.4
  in the current image crashes on *any* Flutter app — a `_stripDocImports`
  RangeError while precaching the Flutter SDK's own `@docImport` comments
  (reproduced with a bare `flutter create`). The step `pub global activate
  dartdoc` (≥ 9.0.9, which fixes it) and runs that. This is really an image bug;
  ContainerHub should ship a newer dartdoc.

- Preset aliases: `clangcl-{debug,profile,release}`, `msvc-{debug,release}`,
  `clang-{debug,profile,release}` → `x64-ClangCL-Windows-Debug` etc.
- Switches: `-SkipTests`, `-SkipFormat`, `-SkipDocs`, `-CleanBuild`, `-SkipMsixPackaging`.
- Logs land in `logs/` (`build-windows-*.log` + `build-summary-*.json`); API
  docs in `doc/api` (git-ignored).

Run the app on the host once artifacts are back:

```powershell
.\scripts\windows\Start-Windows.ps1                                        # release preset
.\scripts\windows\Start-Windows.ps1 -Configuration x64-ClangCL-Windows-Debug
```

Linux builds run containerized. **CI does not use the stage script below.** Its
path is the ContainerHub composite action
`.github/actions/run-in-linux-container@main`, which runs
`scripts/linux/ci/ci-container-run-native-linux.sh` *inside* the container with
CLI flags, not env vars
([`dart_on_native_linux.yml`](.github/workflows/dart_on_native_linux.yml):60,70-78):

```bash
bash /workspace/scripts/linux/ci/ci-container-run-native-linux.sh \
  --flutter-version 3.44.9 --install-flutter true
```

Two flags decide where the SDK comes from: `--install-flutter false` skips the
download entirely and `--flutter-dir <path>` then points at an SDK the image
already carries (`ci-container-run-native-linux.sh`:124 gates the install,
:32 defaults the dir to `/workspace/flutter`). Prefer that over installing —
see *Flutter version pinning* below.

`scripts/linux/ci-dart-on-native-linux.sh <stage>` is the **legacy host-side
driver**, kept for local runs; no workflow references it. Its stages are
`pull_container`, `setup_flutter`, `checks`, `build_linux`, `package`,
`generate_docs`, and it takes its configuration from the environment:

```bash
export MATRIX_ARCH=x64 MATRIX_PLATFORM=linux/amd64      # or: arm64 / linux/arm64
export FLUTTER_VERSION=3.47.1 APP_NAME=kataglyphis-inference-engine
scripts/linux/ci-dart-on-native-linux.sh pull_container
scripts/linux/ci-dart-on-native-linux.sh build_linux
```

**Flutter version pinning — the repo and the image disagree, and the image
wins.** ContainerHub's `linux/scripts/01-core/versions.env` pins
`FLUTTER_VERSION` *together with* its tarball `FLUTTER_SDK_SHA256`; the two are
one pin, so overriding only the version can never verify. The four places this
repo names a version (`dart_on_native_linux.yml`:24,34,
`dart_on_web_linux.yml`:26, `dart_build_android_app.yml`:24) drifted away from
that pin and **all three Flutter CI lanes have been red since 2026-08-12** with
`Checksum verification FAILED`. Passing `FLUTTER_SDK_SHA256` is not a fix from
here: `ci-common.sh`'s `run_container` forwards only four `-e` variables and not
that one. Either match the image's pin or stop pinning in this repo. Whether the
SDK is baked into a given image tag is ContainerHub's business — § 2.

- `require_ci_env` hard-requires `MATRIX_PLATFORM`, `MATRIX_ARCH`,
  `FLUTTER_VERSION` and `APP_NAME` — the script exits rather than guessing.
  Defaulted: `CONTAINER_IMAGE` (`…:latest-cross`), `WORKSPACE_DIR`
  (`/workspace`), `FLUTTER_DIR` (`/workspace/flutter`). The matrix values CI
  uses are in [`dart_on_native_linux.yml`](.github/workflows/dart_on_native_linux.yml).

**`build_linux` on `x64` is not just a build — it is a full CodeQL run.** That
branch downloads the CodeQL CLI, builds a `--db-cluster` for c/cpp/rust and runs
two `database analyze` suites; the actual `flutter build linux --release` only
appears inside the generated `/tmp/codeql-build.sh` that CodeQL invokes. Budget
hours, not minutes. The `arm64` branch is the plain
`flutter clean && flutter pub get && flutter build linux --release`. To build the
app on x64 without the scan, run those three commands through `run_container`
directly instead of the stage.

**`FLUTTER_DIR` defaults inside the workspace**, so the two architectures share
one SDK directory. In CI that is harmless — each runner has its own checkout —
but locally an x64 and an arm64 run in the same tree overwrite each other's SDK.
Run them sequentially, re-running `setup_flutter` before each. (`flutter/*` is
gitignored, so this does not dirty the tree.)

**`run_container` invokes `docker` by name.** On a host whose Linux engine is
containerd rather than dockerd — Rancher Desktop's default — put a `docker`
shim that forwards to `nerdctl` ahead of it on `PATH`, or switch the engine to
`dockerd (moby)`. Host-side setup for that lane (drive mounts, QEMU binfmt for
foreign-arch runs) is ContainerHub's, see § 2.

**`run_container` uses `${GITHUB_WORKSPACE:-$PWD}` as the bind source**, so on a
Windows host set it to the **Windows** path form —
`GITHUB_WORKSPACE='D:\GitHub\Kataglyphis-Inference-Engine'`. A WSL-style
`/mnt/d/...` is accepted, mounts nothing, and reports no error; the build then
fails somewhere far from the cause. From Git Bash also set `MSYS_NO_PATHCONV=1`
so the container-side paths survive. Why this happens is ContainerHub's, § 2.

`package` deletes `~/.pub-cache/hosted` and the build's `obj/` directory before
taring the bundle — it is a CI packaging step, not something to run casually in
a working tree.

Quality gates — `Build-Windows.ps1` runs all three by default (skip with
`-SkipFormat` / `-SkipTests`):

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

The Linux `checks` stage runs the same three (with `dart analyze` rather than
`flutter analyze`) but suffixes each with `|| true`: it reports and moves on
instead of failing the stage. Treat a green `checks` run as "was executed", not
as "passed".

## 5. Docs owned by this repo

- Guides live in `docs/source/` (MyST Markdown, Sphinx via `docs/make.bat` /
  `Makefile`); Dart API docs via `dart doc`.
- [`docs/source/platforms.md`](docs/source/platforms.md) holds the full
  symptom→cause→fix table for containerized Windows builds.
- `docs/source/conf.py` still uses the standalone `press` theme. The shared
  Sphinx theme now lives in **Kataglyphis-DocumANTation** (ContainerHub consumes
  it as a submodule and installs it as `sphinx-kataglyphis-theme`); follow that
  pattern if migrating.
- Update docs in the same PR as user-facing behaviour changes.
