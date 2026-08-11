# AGENTS.md

Guidance for coding agents (and new contributors) working in Kataglyphis-Inference-Engine.

## Project Shape

- **Frontend:** Flutter/Dart app (`lib/`), targets Windows, Linux, Android, and web.
- **Rust core:** `ExternalLib/Kataglyphis-RustProjectTemplate` submodule, bridged via
  `flutter_rust_bridge` (regenerate bindings after Rust API changes:
  `flutter pub run flutter_rust_bridge_codegen`).
- **C++ inference plugin:** `ExternalLib/Kataglyphis_NativeInferencePlugin`
  (`native/KataglyphisCppInference`), links GStreamer + ONNX Runtime via CMake/pkg-config.
- **Build environment:** `ExternalLib/Kataglyphis-ContainerHub` submodule provides the container
  images, the shared PowerShell build modules, the bash build libraries and the CI composite
  actions. **Reuse before you write:** check ContainerHub for an existing helper first — its
  [`docs/adopting-in-a-new-project.md`](ExternalLib/Kataglyphis-ContainerHub/docs/adopting-in-a-new-project.md)
  is the map. This repo's glue is deliberately thin:
  - `scripts/windows/Resolve-BuildModule.ps1` — the one file that cannot live upstream, because
    it is what *finds* the submodule. `Import-BuildModule <Name>` resolves
    `ExternalLib/Kataglyphis-ContainerHub/windows/scripts/modules/<Name>.psm1` **first**, then
    `scripts/windows/modules/<Name>.psm1`. Put a module upstream and it wins automatically; the
    local directory holds only genuinely project-specific ones (today: `Windows.Paths`, which
    encodes this repo's Flutter `build/windows/x64/{runner,plugins}` layout).
  - `scripts/linux/lib/containerhub.sh` — the bash twin: `containerhub_source <relative/path>`
    and `containerhub_path <relative/path>`, resolved from `${BASH_SOURCE[0]}` so they work
    from any working directory.
  - Workflows call ContainerHub's composite actions (`prepare-linux-ci-host`,
    `run-in-linux-container`, `run-in-windows-container`, `cleanup-disk-space`) at `@main`.
    Because actions resolve at `@main`, a ContainerHub change a workflow depends on must be
    pushed **before** the consumer change.
- **Windows webcam inference:** the Stream page runs a Rust-owned webcam → ONNX → Flutter-texture
  pipeline (`crates/media` GStreamer capture → `src/webcam_engine.rs` → frb `src/api/webcam.rs`
  stream; frames reach the texture via the native plugin's `knt_push_frame` C ABI, only detection
  metadata crosses the bridge). Gated by Rust features `gstreamer,onnxruntime_dynamic,onnxruntime_directml`,
  enabled on Windows through the `KATAGLYPHIS_RUST_FEATURES` env var (forwarded to cargo by
  `rust_builder`'s CMake → Cargokit). `mfvideosrc` (Media Foundation) needs the `mediafoundation`
  GStreamer plugin **and** a Windows client host; it falls back to `ksvideosrc`. See
  `docs/source/camera-streaming.md` § *Windows: Rust-owned webcam inference*.

## Windows Builds (containerized, matches CI)

Windows builds run inside `ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64`. The container
engine is [Stevedore](https://github.com/slonopotamus/stevedore) — use its bundled `docker.exe`
(`"$env:ProgramFiles\Stevedore\bin\docker.exe"`), never `nerdctl` (broken DNS / missing CNI).
Setup and post-install fixes are documented in Kataglyphis-ContainerHub
(`docs/windows-builds.md`, § Stevedore Setup Fixes).

Run build containers with **process isolation**, as described in Kataglyphis-ContainerHub —
Hyper-V isolation (the Windows default) caps containers at 2 logical CPUs:

```powershell
& "$env:ProgramFiles\Stevedore\bin\docker.exe" run --rm --isolation process `
  --mount "type=bind,source=$PWD,target=C:\workspace" -w C:\workspace `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64 `
  pwsh -NoProfile -ExecutionPolicy Bypass -File C:\workspace\scripts\windows\build-windows.ps1 `
    -Configurations "clangcl-debug,clangcl-profile,clangcl-release" -SkipMsixPackaging
```

- `--isolation process` is for `docker run` ONLY. Never pass it to `docker build`
  (layer commits fail — see ContainerHub `docs/windows-builds.md`).
- Preset aliases: `clangcl-{debug,profile,release}`, `msvc-{debug,release}`,
  `clang-{debug,profile,release}` → `x64-ClangCL-Windows-Debug` etc.
- Useful switches: `-SkipTests`, `-SkipFormat`, `-CleanBuild`, `-SkipMsixPackaging`.
- Build logs land in `logs/` (`build-windows-*.log` + machine-readable
  `build-summary-*.json`).

Run the app on the host after artifacts are back:

```powershell
.\scripts\windows\Start-Windows.ps1                                        # x64-ClangCL-Windows-Release
.\scripts\windows\Start-Windows.ps1 -Configuration x64-ClangCL-Windows-Debug
```

## Known Pitfalls

- **Dev Drive blocks bind mounts.** If the repo sits on a Dev Drive (ReFS dev volume), Windows
  containers cannot bind-mount it ("Dateisystem-Minifilter kann nicht an das Entwicklervolume
  angefügt werden"). One-time fix from an elevated shell, then remount/reboot:
  `fsutil devdrv setfiltersallowed bindFlt, wcifs`. Non-admin fallback (preferred): mirror the
  repo to a plain NTFS path (`robocopy D:\GitHub\... C:\kata-ws /E /MT:16 /XJ /XD .dart_tool build logs`)
  and bind-mount `C:\kata-ws`. Two caveats: **the mount target must not already exist in the
  image** (`target=C:\workspace` fails `CreateComputeSystem: Die Anforderung wird nicht
  unterstützt`; use `target=C:\ws-mnt` + `-w C:\ws-mnt`), and **Dart's `copySync`/`renameSync`
  fail on mounted paths** (writes and cmd copy/ren work) — junction `.dart_tool` and `build`
  from the mounted workspace to container-local dirs (`mklink /J C:\ws-mnt\.dart_tool C:\dtool`
  etc., from inside the container) before building. Last resort:
  tar-stream sources into a long-lived container over `docker exec -i` (`tar -cf - . | docker exec
  -i <name> tar -xf - -C C:\workspace`). `docker cp` into a running Windows container silently
  copies nothing.
- **PowerShell 7 is mandatory.** Every ContainerHub build module declares
  `#requires -Version 7.0`, so `build-windows.ps1` and `Start-Windows.ps1` do too. Launch them
  with `pwsh`, never Windows PowerShell 5.1's `powershell` — under 5.1 the failure surfaces as
  an opaque `Import-Module` error in the preamble.
- **Entrypoint vs `docker exec`.** The image's entrypoint (`C:\temp\scripts\entrypoint.cmd`)
  loads VsDevCmd; `docker exec` bypasses it. When exec-ing builds, wrap them:
  `docker exec <name> cmd /S /C "C:\temp\scripts\entrypoint.cmd powershell ..."`.
- **Intermittent ENOENT under process isolation.** On a client host (build 26200) running the
  Server-based image (26100), the `wcifs` filter occasionally fails file creation/rename inside
  image-layer directories with "path not found" (same skew that breaks `docker build
  --isolation process` layer commits — see ContainerHub `docs/windows-builds.md`). Symptoms seen:
  `git init/clone` failing with "could not write config file", `PathNotFoundException` renaming
  downloaded native assets. Freshly created sandbox directories (e.g. `C:\probe`) are reliable;
  retry the failed step, or route heavy file writes through `tar`.
- **pkg-config:** the native inference plugin requires `pkg-config` and the image's baked
  `PKG_CONFIG_PATH` (GStreamer/FFmpeg/OpenCV `.pc` files under `C:\runtime`). If the image lacks
  a pkg-config binary, `scoop install pkg-config` inside the container unblocks it (the durable
  fix belongs in the ContainerHub image).
- **Cargokit needs rustup.** The `rust_builder` Flutter plugin builds its crate via Cargokit
  during CMake install, and Cargokit hard-requires rustup — which the image omits (scoop-only
  Rust). Install rustup **with a default toolchain** in the container
  (`C:\rustup-init.exe -y --default-toolchain stable --profile minimal`); only toolchain-less
  rustup shims are harmful.
- **clangcl-Debug preset ships with ASAN ON** and builds + runs green (see the ASAN bullet
  below for how — Microsoft's runtime, no `/MT` overrides, `-shared-libsan`). Historic
  gotchas now fixed: naive ASAN dragged `/MT` into Flutter's `/MD` objects (`lld-link`
  RuntimeLibrary mismatch), and `kataglyphis_libfuzzer.exe` hit an `annotate_string` mismatch
  vs `clang_rt.fuzzer`. All resolved in the plugin's `cmake/Sanitizers.cmake` +
  `ExternalLib/CMakeLists.txt`.
- **Shared install dir:** all presets install into
  `build\windows\x64\runner\x64-ClangCL-Windows-Release\` — the folder holds whichever preset
  built last; copy artifacts away between preset runs.
- **Running on an unprovisioned host** (`STATUS_DLL_NOT_FOUND`): stage the image's runtime DLLs
  into the runner (`C:\runtime\bin` + onnxruntime/DirectML → `runner\bin\`;
  `C:\runtime\lib\gstreamer-1.0` → `runner\lib\gstreamer-1.0\`). Two extra gotchas when copying
  the runner out to a plain host: `KataglyphisCppInference.dll` is built into a `bin\` **subdir**
  of the runner (the native plugin needs it **next to the exe** — copy it up), and the VC++
  runtime (`msvcp140.dll`, `vcruntime140*.dll`) isn't bundled (stage the VC redist CRT DLLs).
  A healthy launch is ~130 MB with a real window; a ~6 MB process that exits means a missing
  dependency DLL. Full symptom table in `docs/source/platforms.md`.
- **`docker commit` needs hyperv isolation.** Containers created with `--isolation process`
  can't be committed on the skewed host (`ActivateLayer 0x20`), and Windows containers can't be
  `docker export`ed. Create anything you intend to commit (e.g. a rebuilt `windows-media`) with
  `--isolation hyperv`.

- **sccache is C++20-module-blind.** Its cache key ignores imported BMI *content*, so after
  changing flags on a module target (`nlohmann_json_modules`, `tomlplusplus_modules`, `.ixx`
  targets), importers get stale cached objects with the old BMI's linker directives. After any
  module-flag change: clean the build dir AND build once with `SCCACHE_RECACHE=1`.
- **ASAN under clang-cl + Flutter runs the full app** — but only against **Microsoft's** ASan
  runtime, not LLVM's. Build-time needs a dynamic CRT throughout (`-shared-libsan`, no `/MT`
  overrides anywhere — module BMIs re-emit `detect_mismatch` directives into importers, so one
  `/MT` BMI poisons everything). At run time, LLVM's `clang_rt.asan_dynamic` loads *after*
  ucrtbase, so allocations made during CRT/COM startup are unhooked and LLVM's runtime aborts
  with an unsuppressible `bad-free` when combase/ole32 later free them. Microsoft's ASan runtime
  (shipped with VS BuildTools, `VC\Tools\MSVC\<ver>\bin\Hostx64\x64\clang_rt.asan_dynamic-x86_64.dll`)
  tracks Windows heap ownership correctly and passes those foreign frees through. The plugin's
  `cmake/Sanitizers.cmake` links Microsoft's thunk + import lib (same filenames as LLVM's — it
  just points the link-search at MSVC's `lib\x64`) while keeping clang's own instrumentation;
  `Start-Windows.ps1` stages Microsoft's DLL next to the exe and sets
  `ASAN_OPTIONS=alloc_dealloc_mismatch=0:check_malloc_usable_size=0`. Net: the clang-cl Debug
  preset ships with ASAN **ON** and the full app runs clean under it (Dart VM up, camera live).
- **Vendored ANTLR (dragged in unconditionally by newer FUZZTEST):** needs `WITH_STATIC_CRT
  OFF`, `ANTLR_BUILD_CPP_TESTS OFF`, `ANTLR_BUILD_SHARED OFF`, `/FIchrono`, and `LICENSE.txt`
  staged at the build root (its install rule assumes a monorepo layout). All wired up in the
  plugin's `ExternalLib/CMakeLists.txt`.

Full symptom→cause→fix table: `docs/source/platforms.md` § *Troubleshooting containerized
Windows builds*.

## Quality Gates

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

`build-windows.ps1` runs all three by default (skip with `-SkipFormat` / `-SkipTests`).

## Documentation

- Guides live in `docs/source/` (MyST Markdown, Sphinx via `docs/make.bat` / `Makefile`);
  Dart API docs via `dart doc`.
- The shared Sphinx theme/template was moved out of Kataglyphis-ContainerHub into the
  **Kataglyphis-DocumANTation** repository (ContainerHub consumes it as submodule
  `external/Kataglyphis-DocumANTation`, installed via `requirements.txt` as the editable package
  `sphinx-kataglyphis-theme`; `conf.py` reduces to `from sphinx_kataglyphis import setup_theme`).
  This repo's `docs/source/conf.py` still uses the standalone `press` theme — follow the
  ContainerHub pattern if/when migrating.
- Update docs in the same PR as user-facing behavior changes.
