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
  images and the shared PowerShell build modules imported by `scripts/windows/Build-Windows.ps1`.

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
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\workspace\scripts\windows\Build-Windows.ps1 `
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
- **ContainerHub submodule pin.** `Build-Windows.ps1` imports `WindowsToolchain.Common.psm1`,
  `WindowsFlutter.Common.psm1`, `WindowsCodeQL.Common.psm1` from the ContainerHub submodule.
  ContainerHub's newer `main` deleted these; build against the commit recorded by this repo
  (`git submodule update ExternalLib/Kataglyphis-ContainerHub`).
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
- **clangcl-Debug preset is broken upstream** (CI only builds the default Release path):
  ASAN defaults ON for clang-cl Debug (`ProjectOptions.cmake`) and drags `/MT` into Flutter's
  `/MD` objects → `lld-link` RuntimeLibrary mismatch; with ASAN off, `kataglyphis_libfuzzer.exe`
  hits an `annotate_string` mismatch vs `clang_rt.fuzzer`. Workaround: Debug preset with
  sanitizers OFF + `BUILD_TESTING: FALSE`.
- **Shared install dir:** all presets install into
  `build\windows\x64\runner\x64-ClangCL-Windows-Release\` — the folder holds whichever preset
  built last; copy artifacts away between preset runs.
- **Running on an unprovisioned host** (`STATUS_DLL_NOT_FOUND`): stage the image's runtime DLLs
  into the runner (`C:\runtime\bin` + onnxruntime/DirectML → `runner\bin\`;
  `C:\runtime\lib\gstreamer-1.0` → `runner\lib\gstreamer-1.0\`).

- **sccache is C++20-module-blind.** Its cache key ignores imported BMI *content*, so after
  changing flags on a module target (`nlohmann_json_modules`, `tomlplusplus_modules`, `.ixx`
  targets), importers get stale cached objects with the old BMI's linker directives. After any
  module-flag change: clean the build dir AND build once with `SCCACHE_RECACHE=1`.
- **ASAN under clang-cl + Flutter works at build time** (dynamic CRT throughout:
  `-shared-libsan`, no `/MT` overrides anywhere — module BMIs re-emit `detect_mismatch`
  directives into importers, so one `/MT` BMI poisons everything). **Running the full Flutter
  app under ASAN aborts** on mixed-instrumentation false positives (`bad-malloc_usable_size`,
  then `bad-free`) because the uninstrumented engine DLLs share the hot-patched CRT heap — a
  documented Windows ASAN limitation, not an app bug. Use ASAN via the plugin's own
  test/fuzz executables; run the app itself without the ASAN runtime loaded.
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

`Build-Windows.ps1` runs all three by default (skip with `-SkipFormat` / `-SkipTests`).

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
