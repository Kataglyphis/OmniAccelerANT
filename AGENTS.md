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
| `ExternalLib/Kataglyphis-RustProjectTemplate` | Rust core, bridged via `flutter_rust_bridge` — regenerate bindings with `flutter_rust_bridge_codegen generate` (a cargo binary baked into the build image, NOT a pub dependency; on a bare host `cargo install flutter_rust_bridge_codegen` first). `lib/src/rust/` is committed generated code — no build lane regenerates it |
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
| appimagetool provisioning — pinned version + SHA256, not the moving `continuous` tag | `linux/scripts/02-toolchain/packaging-deps.sh`, subcommand `appimagetool` |
| Python venv + `uv` provisioning (installer downloaded to a file and SHA-checkable, never `curl \| sh`) | `linux/scripts/01-core/python_uv.sh` |
| The Dart gate for Linux lanes — deps, format, analyze, test, `--strict`/`--extra-package` | `linux/scripts/05-frameworks/flutter/flutter_checks.sh` |

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
  genuinely project-specific modules (today: `WindowsPaths.Common`, encoding this
  repo's Flutter `build/windows/x64/{runner,plugins}` layout).
- `scripts/linux/lib/containerhub.sh` — the bash twin: `containerhub_source`
  and `containerhub_path`, resolved from `${BASH_SOURCE[0]}` so they work from
  any working directory.

**Deliberately not reused.** Two upstream Windows pieces were evaluated and
rejected; both would be regressions here, so do not "fix" their absence:

- `WindowsAppRunner.Common` (`Invoke-AppRun` / `Resolve-AppExecutablePath`).
  Its executable probe tries `<BuildRoot>\<exe>` first and ends in a recursive
  first-match search. This tree holds **four** copies of the runner exe
  (`runner\`, `runner\Release\` from the MSIX layout step, `runner\<preset>\`,
  `runner\<preset>\Release\`), so it would launch the flat one and ignore
  `-Configuration` entirely. `Start-Windows.ps1` instead resolves through
  `Resolve-KataglyphisWindowsLayout`, which knows the preset layout and
  validates the Rust plugin DLL alongside the exe. `Invoke-AppRun` also has no
  log parameter, so adopting it would drop the `Tee-Object` run log.
- `Invoke-CmakeConfigureAndBuild` (`WindowsCMake.Common`). It makes `-Preset`
  mandatory (this repo also has a generator/`CMAKE_BUILD_TYPE` path), passes no
  `-S` source directory (the CMake source here is `windows/`, not the repo
  root), and offers no `--target` — but `--target install` is what produces the
  runner bundle. It also fuses configure and build into one step, while the
  `Native Assets Directory Fix` step must run between them.

## 3. Pitfalls specific to this project

Everything here is false or meaningless in another repo — that is why it is
written out rather than linked.

- **Never `dart format .` here.** The Linux lanes install the Flutter SDK
  *inside* the mounted workspace (`flutter_dir: /workspace/flutter`), so the
  recursive walk formats the SDK itself. Run 33810449411 (2026-09-03) reported
  `Formatted 7404 files (627 changed)` with 604 of those under `flutter/` —
  by itself enough to fail `--set-exit-if-changed`, and it rewrites the SDK on
  disk on the way. Both lanes now list tracked files instead:
  `code_quality_find_dart_files` on Linux, `Get-ProjectDartFiles` on Windows;
  they return the same 60 files. A local checkout hits this too — a full
  Flutter SDK at `<repo>/flutter` is gitignored but very much still on disk.
  `dart analyze` is *not* affected and never was: it honours the
  `analyzer.exclude` list in `analysis_options.yaml`, which already names
  `flutter/**`, `ExternalLib/**` and `rust_builder/**`. `dart format` ignores
  that file entirely — which is the whole reason the file list has to be built
  outside it, and why the two helpers use exactly those three exclusions.

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
- **Each preset installs into its own directory** —
  `build\windows\x64\runner\<preset>\` (and `plugins\<preset>\`), because
  `Build-Windows.ps1`:367 resolves the layout per preset and :399/:408 pass that
  as `-DCMAKE_INSTALL_PREFIX`. `x64-ClangCL-Windows-Release` is only the fallback
  used when no preset is named (`WindowsBuildConfig.ps1`'s `CMakeConfiguration`).
  Presets no longer clobber each other — but `Start-Windows.ps1` must then be
  given the same preset name.
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

Three quality/output steps run before the native build (`-CodeQL` short-circuits
before them), each skippable with the paired switch: **Dart format**
(`-SkipFormat`), **Dart analyze + Flutter tests** (`-SkipTests`), **API docs
generation** (`-SkipDocs`).

**A failed step does not abort the run.** None of them is declared `-Critical`,
and `-StopOnError` is off by default, so the step is recorded and the build
carries on — the log still ends with `=== Build Complete ===` even when
something failed, and the script only exits 1 from its `finally` block. A real
run shows both lines together (`FAILED: MSIX Packaging` … `=== Build Complete ===`).
**Trust the process exit code and `failedSteps` in `logs/build-summary-*.json`,
never the log tail.**

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
- Switches: `-SkipTests`, `-SkipFormat`, `-SkipDocs`, `-CleanBuild`, `-SkipMsixPackaging`,
  `-SkipBootstrapFlutterBuild`, `-ContinueOnError`/`-StopOnError`, `-CodeQL`. The
  closing **Delivery Check** cannot be skipped.
- Logs land in `logs/` (`build-windows-*.log` + `build-summary-*.json`); API
  docs in `doc/api` (git-ignored).

**MSIX packaging.** `msix_config.build_windows` is `false` on purpose: this
script owns the build, and letting msix run its own `flutter build windows`
makes it trip over the `CMakeCache.txt` synced back from the container-local
build root (*"the current CMakeCache.txt directory … is different than the
directory … where it was created"*, plus the wrong generator). The
**MSIX Compatibility Layout** step exists because msix looks for
`build\windows\x64\runner\Release\`, while the build installs to
`runner\<preset>\`; it copies the preset's output into that flat `Release\`.
Both halves were broken until 2026-09-03 and nobody noticed, because CI passes
`-SkipMsixPackaging` — packaging is only exercised locally.

**The CI lane** ([`dart_on_native_windows.yml`](.github/workflows/dart_on_native_windows.yml))
is four ContainerHub actions and nothing hand-rolled:
`prepare-windows-container-host` (long paths, short-path clone, data-root move,
disk check, GHCR login, pull), `run-in-windows-container`,
`actions/upload-artifact` and `upload-codeql-sarif`. Three consequences:

- It prunes `external/Kataglyphis-DocumANTation` from the recursive checkout.
  This repo's chain is Inference-Engine → NativeInferencePlugin →
  KataglyphisCppInference → ContainerHub → DocumANTation → md2pdfLib →
  `latex/{smile,awesome-beamer}`, and every level adds another
  `.git/modules/<name>/` segment until git aborts with `fatal: '$GIT_DIR' too
  big` — that is git's own limit, not MAX_PATH, so no clone root is short
  enough. DocumANTation is ContainerHub's LaTeX tooling and the Windows build
  never reads it.
- `mount-source`/`mount-target` stay unset: the action already defaults to
  `D:\ws` → `C:\ws`, which is where the short-path clone put the tree. Setting
  them to `github.workspace` would mount the submodule-less checkout instead.
- Artifact paths are therefore **absolute under the short-path clone**
  (`steps.prep.outputs.workspace`), never relative to `github.workspace`. A
  relative path matches nothing there, and `if-no-files-found: error` would
  report that as a missing build. `upload-codeql-sarif` exists for the same
  reason: `hashFiles()` only sees inside `GITHUB_WORKSPACE`.

CI passes `-SkipMsixPackaging`, and `-CodeQL` is off there because of runtimes.

Run the app on the host once artifacts are back:

```powershell
# -Configuration is required: it names the runner\<preset>\ directory to launch.
.\scripts\windows\Start-Windows.ps1 -Configuration x64-ClangCL-Windows-Release
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
  --install-flutter true
```

Two flags decide where the SDK comes from: `--install-flutter false` skips the
download entirely and `--flutter-dir <path>` then points at an SDK the image
already carries (`ci-container-run-native-linux.sh` gates the install on
`--install-flutter`, and defaults the dir to `/workspace/flutter`). Prefer that
over installing —
see *Flutter version pinning* below.

`scripts/linux/ci-dart-on-native-linux.sh <stage>` is the **legacy host-side
driver**, kept for local runs; no workflow references it. Its stages are
`pull_container`, `setup_flutter`, `checks`, `build_linux`, `package`,
`generate_docs`, and it takes its configuration from the environment:

```bash
export MATRIX_ARCH=x64 MATRIX_PLATFORM=linux/amd64      # or: arm64 / linux/arm64
# This legacy driver never calls resolve_flutter_pin, and ci-common.sh hard-requires
# the variable — so hand it the same pin ContainerHub owns rather than typing one:
export FLUTTER_VERSION=$(sed -n 's/^FLUTTER_VERSION=//p' \
  ExternalLib/Kataglyphis-ContainerHub/linux/scripts/01-core/versions.env)
export APP_NAME=kataglyphis-inference-engine
scripts/linux/ci-dart-on-native-linux.sh pull_container
scripts/linux/ci-dart-on-native-linux.sh build_linux
```

**Flutter version pinning — ContainerHub owns it; this repo derives it and
names it nowhere.** `linux/scripts/01-core/versions.env` pins `FLUTTER_VERSION`
(:323) *together with* its tarball `FLUTTER_SDK_SHA256` (:700); the two are one
pin, so overriding only the version can never verify. This repo used to name the
version in four places, they drifted, and **all three Flutter lanes were red
from 2026-08-12** with `Checksum verification FAILED`. They name it nowhere now:
`resolve_flutter_pin` (`scripts/linux/lib/container-steps.sh`) reads BOTH keys
out of that one file and exports the sha, and all three Linux lanes call it.
**To bump Flutter, bump the ContainerHub submodule.**

Exporting the sha is the load-bearing half. ContainerHub's
`05-frameworks/flutter/setup-flutter.sh`:97 only falls back to the copy baked
into the image (`/opt/scripts/core/versions.env`, `Dockerfile.sdk`:111) when
`FLUTTER_SDK_SHA256` is unset — and that copy tracks the floating
`:latest-cross` tag, not our submodule pointer. The native and android lanes
already exported it via `packaging-common.sh` -> `common.sh`; the **web lane
does not source those**, so it alone used to verify against the image. That
asymmetry is why a version and a sha from different files could ever meet.
`--flutter-version <ver>` still overrides for a deliberate one-off; the pinned
sha is then deliberately not exported, so `setup-flutter.sh`:118-126 can name
the mismatch instead of emitting a bare checksum error. Whether the SDK is baked
into a given image tag is ContainerHub's business — § 2.

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

Quality gates — `Build-Windows.ps1` runs these by default (skip with
`-SkipFormat` / `-SkipTests` / `-SkipDocs`). Note the format command is **not**
`dart format .`: that is the form documented above as crashing on Windows.

```bash
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze
flutter test
dart pub global run dartdoc --output doc/api
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
