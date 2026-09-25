# Platform Guides

Build and run instructions by target platform.

## Container Setup (Linux/WSL)

To run a command in the family Linux CI image, use ANTfrastructure's driver
rather than typing an engine line. It owns the image reference, the bind mount
at `/workspace` and the `safe.directory` that mount needs, picks `nerdctl` or
`docker` for you, and sets the `MSYS_NO_PATHCONV` a Git Bash caller needs:

```bash
bash third_party/ANTfrastructure/linux/scripts/run-in-ci-image.sh . -- flutter --version
```

The **Stream demo** needs three things that driver deliberately does not expose
— an interactive TTY, published ports and a `--device` passthrough — so it stays
a direct engine call. The image reference is still not typed here: the same
`ci-image-ref.sh` the driver calls composes it out of the hub's `versions.env`,
which is the family's one owner of both CI image refs.

```bash
IMAGE="$(bash third_party/ANTfrastructure/linux/scripts/ci-image-ref.sh)"
docker run -it --rm \
  -v "$(pwd)":/workspace \
  -w /workspace \
  -p 9090:9090 \
  -p 8443:8443 \
  -p 8444:8444 \
  -p 5173:5173 \
  --device=/dev/video0 \
  "${IMAGE}"
```

For WSL2 camera passthrough, ensure the USB device is attached before running the container.

## Windows Development

### Containerized build (Stevedore, recommended)

Windows builds run inside the `kataglyphis_beschleuniger:winamd64` image from
[ANTfrastructure](https://github.com/Kataglyphis/ANTfrastructure) — the same
image CI uses. The container engine on Windows is
[Stevedore](https://github.com/slonopotamus/stevedore) (`winget install stevedore`); bring the
host up with ANTfrastructure's `docs/windows-host-setup.md` (Phase A), apply the
post-install fixes in its `docs/windows-stevedore-and-docker.md` (§ Stevedore Setup
Fixes), and always use Stevedore's bundled `docker.exe`, not `nerdctl`:

```powershell
$docker = "$env:ProgramFiles\Stevedore\bin\docker.exe"
& $docker pull ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64
```

Run the build container with **process isolation** (`--isolation process`) — it
gives the container the host's full CPU count instead of the Hyper-V default's 2,
and must never be passed to `docker build`. The engine rationale, the CPU/base-build
caps, and the `docker build` prohibition are ANTfrastructure's, not this project's — see
[`windows-build-lanes.md`](../../third_party/ANTfrastructure/docs/windows-build-lanes.md).

```powershell
& $docker run --rm --isolation process `
  --mount "type=bind,source=$PWD,target=C:\ws-mnt" -w C:\ws-mnt `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64 `
  pwsh -NoProfile -ExecutionPolicy Bypass -File C:\ws-mnt\scripts\windows\Build-Windows.ps1 `
    -Configurations "clangcl-debug,clangcl-profile,clangcl-release" -SkipMsixPackaging
```

`-Configurations` accepts the preset aliases `clangcl-debug`, `clangcl-profile`,
`clangcl-release` (also `msvc-*`, `clang-*`), which map to the
`x64-ClangCL-Windows-{Debug,Profile,Release}` CMake presets.

> **Dev Drive caveat:** if the repo lives on a Dev Drive (ReFS dev volume), the bind mount fails
> with *"Der Dateisystem-Minifilter kann nicht an das Entwicklervolume angefügt werden"* — Dev
> Drives block the `bindFlt`/`wcifs` container filters by default. Allow them once from an
> **elevated** shell, then remount the volume (or reboot):
>
> ```powershell
> fsutil devdrv setFiltersAllowed /volume D: "bindFlt,wcifs"
> ```
>
> The filter list must be **one quoted argument** — unquoted `bindFlt, wcifs` is parsed as two
> and fails with a bare syntax dump. ANTfrastructure owns this procedure, including the reboot
> requirement, the "allowed vs attached" distinction and how to revert it:
> `third_party/ANTfrastructure/docs/windows-container-build-performance.md`
> § *Transport B*. Everything below this line is Flutter/Dart-specific and belongs here.
>
> Non-admin workaround (preferred): mirror the repo to a plain NTFS path on `C:` and bind-mount
> that — bind mounts from non-Dev-Drive volumes work fine. Caveat: **Dart's `copySync`/
> `renameSync` fail on bind-mounted paths** on this host (plain writes and cmd copy/ren work),
> so after mounting, junction Flutter's write dirs to container-local paths from *inside* the
> container before building:
>
> ```powershell
> docker exec <name> cmd /c "mkdir C:\dtool & mkdir C:\fbuild\native_assets\windows & mklink /J C:\ws-mnt\.dart_tool C:\dtool & mklink /J C:\ws-mnt\build C:\fbuild"
> ```
>
> ```powershell
> robocopy D:\GitHub\OmniAccelerANT C:\kata-ws /E /MT:16 /XJ /XD .dart_tool build logs
> & $docker run --rm --isolation process `
>   --mount "type=bind,source=C:\kata-ws,target=C:\ws-mnt" -w C:\ws-mnt `
>   ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64 `
>   pwsh -NoProfile -ExecutionPolicy Bypass -File C:\ws-mnt\scripts\windows\Build-Windows.ps1 `
>     -Configurations "clangcl-debug,clangcl-profile,clangcl-release" -SkipMsixPackaging
> ```
>
> **Mount target must NOT already exist in the image** on this host: targeting the baked
> `C:\workspace` fails with `hcs::CreateComputeSystem ... Die Anforderung wird nicht unterstützt`
> (same 26200-host / 26100-image skew family). Use a fresh target like `C:\ws-mnt`. CI on
> version-matched runners can mount over `C:\workspace` without issue.
>
> Last resort (no mount at all): tar-stream the sources into a long-lived container over
> `docker exec -i` (`tar -cf - . | docker exec -i <name> tar -xf - -C C:\workspace`). Note that
> `docker cp` into a running Windows container silently copies nothing — use the tar stream.

> **ANTfrastructure submodule:** `scripts/windows/Build-Windows.ps1` resolves every PowerShell
> module through `scripts/windows/Resolve-BuildModule.ps1`, which looks in
> `third_party/ANTfrastructure/windows/scripts/modules/` first and only then in
> `scripts/windows/modules/`. Check the submodule out before building
> (`git submodule update --init --recursive third_party/ANTfrastructure`); a missing
> one is reported by name with that exact command. All those modules declare
> `#requires -Version 7.0`, hence `pwsh` rather than `powershell` in the commands above.

Run the app on the host after a build:

```powershell
.\scripts\windows\Start-Windows.ps1                                        # runner\Release: the MSIX copy of the first preset built
.\scripts\windows\Start-Windows.ps1 -Configuration x64-ClangCL-Windows-Debug
```

### Troubleshooting containerized Windows builds

| Symptom | Cause | Fix |
|---------|-------|-----|
| CMake: `Could NOT find PkgConfig` | The winamd64 image bakes `PKG_CONFIG_PATH` + `.pc` files (`C:\runtime\...`), and older builds of it shipped **no pkg-config binary**. Fixed in the image since: its `Install-ScoopTools.ps1` installs pkg-config (hub `docs/windows-builds.md` § *Toolchain pins and the provenance manifest*) | Pull a current `:winamd64`; a reappearance is an image regression. On an old image, `scoop install pkg-config` inside the container (there is no `pkgconf` manifest). |
| Cargokit: `rustup not found in PATH.` during CMake install | The Flutter plugin `rust_builder` builds its Rust crate via Cargokit, which hard-requires rustup; older builds of the image were scoop-Rust-only. Fixed in the image since: `Install-RustToolchain.ps1` provisions rustup with a default toolchain (hub `docs/windows-builds.md` § *Rust toolchain*) | Pull a current `:winamd64`. On an old image, in the container: `Invoke-WebRequest https://win.rustup.rs/x86_64 -OutFile C:\rustup-init.exe; C:\rustup-init.exe -y --default-toolchain stable --profile minimal`. A rustup **with** a default toolchain is safe — ANTfrastructure's warning targets toolchain-less rustup shims only. |
| `PathNotFoundException ... sqlite3.dll.tmp` in `flutter assemble` | Dart's `renameSync`/`copySync` fail (errno 3) in container-layer dirs **and on bind-mounted paths** on this skewed host — the sqlite3 hook downloads fine, then dies on the two-path file op | Junction `.dart_tool` and `build` to fresh **container-local** dirs (`mklink /J`, from inside the container) — Dart ops work there. Hook patching (`renameSync` → direct `openWrite` to the final name) is a fallback if junctions are impossible. |
| `lld-link ... mismatch detected for 'RuntimeLibrary'` (Debug preset) | A `/MT` override (root `CMAKE_MSVC_RUNTIME_LIBRARY`, an abseil `/MT` hack, or a C++20 module BMI built `/MT` re-emitting `detect_mismatch` into importers) collides with Flutter's `/MD` | Remove **every** `/MT` override and compile ASAN with `/clang:-shared-libsan` so clang emits dynamic-CRT link directives. All wired up in the upstream module `third_party/ANTfrastructure/cmake/Sanitizers.cmake`, reached via `CMAKE_MODULE_PATH` (the inference core's own copy is retired), plus the no-`/MT` policy in `third_party/AccelerANTgine/third_party/CMakeLists.txt`. Diagnose stray directives with `llvm-readobj --coff-directives <obj>`. |
| Instrumented app dies instantly `STATUS_ENTRYPOINT_NOT_FOUND` (−1073741511) | The staged `clang_rt.asan_dynamic-x86_64.dll` is LLVM's, but the binary's baked-in thunk imports Microsoft-named allocator forwarders (`__asan_new`, `__asan_delete`, …), or vice-versa | Link **and** stage a matched pair. The Debug preset links Microsoft's thunk+import lib (ANTfrastructure's `cmake/Sanitizers.cmake`, on `CMAKE_MODULE_PATH`, points the link-search at `VC\Tools\MSVC\<ver>\lib\x64`); `Start-Windows.ps1` stages the matching `clang_rt.asan_dynamic-x86_64.dll` from the same MSVC dir. |
| Instrumented app aborts on startup with `bad-free` / `bad-malloc_usable_size` | LLVM's ASan runtime loads after ucrtbase, so CRT/COM startup allocations are unhooked and abort when freed through interceptors | Use **Microsoft's** ASan runtime (VS BuildTools) — it tracks Windows heap ownership and passes foreign frees through — plus `ASAN_OPTIONS=alloc_dealloc_mismatch=0:check_malloc_usable_size=0`. This is the shipped Debug-preset config; the full app runs clean under it. |
| App exits with `STATUS_DLL_NOT_FOUND` (−1073741515) on a host without GStreamer/ONNX installs | The native plugin links GStreamer + ONNX Runtime, provided by `C:\runtime` in the container, `C:\Program Files\gstreamer` + `C:\onnxruntime` on a provisioned host | Stage from the image into the runner: `C:\runtime\bin\*.dll` except `onnxruntime*.dll`/`DirectML.dll` → `runner\...\bin\` (ONNX Runtime is already beside the exe: `Build-Windows.ps1` stages the chain copy and `Start-Windows.ps1` refuses any other, AGENTS.md § 4); `C:\runtime\lib\gstreamer-1.0\` → `runner\...\lib\gstreamer-1.0\` (GStreamer locates plugins relative to its core DLL). `Start-Windows.ps1` puts `runner\bin` on `PATH`. With the Rust `gstreamer` feature on (the Windows default) the build's *Bundle Media Runtime DLLs* step already copies `C:\runtime\bin\*.dll` (ORT family excluded) beside the exe and ten capture plugins into `gstreamer-1.0\`. |
| `git init/clone/checkout` fails with `could not write config file` / `unable to write new index file` inside the container | Same `wcifs` rename/create flakiness in layer dirs | Do git surgery outside the layer zone (fresh `C:\` dirs work), or `git archive | tar -x` trees into place; a bind-mounted workspace avoids it entirely. |
| `docker run --mount` fails: `hcs::CreateComputeSystem ... Die Anforderung wird nicht unterstützt` although the source is plain NTFS | The mount **target** already exists in the image (e.g. baked `C:\workspace`) — refused on skewed hosts | Mount to a path that does not exist in the image (e.g. `target=C:\ws-mnt`) and pass `-w C:\ws-mnt`. |
| `docker commit` (or `docker start` of a stopped container) fails `hcsshim::ActivateLayer ... (0x20)` | The container was created with `--isolation process`; on this host its writable layer stays locked after stop and cannot be snapshotted | Create any container you intend to **commit** with `--isolation hyperv` (kept-alive + `docker exec` build + stop + commit works — this is why the ANTfrastructure orchestrator uses hyperv for run+commit). `docker export` is **not** a workaround (the daemon refuses to export Windows containers). Reserve `--isolation process` for throwaway runs whose output you extract *live* via `tar` over `docker exec` before stopping. |
| `mediafoundation` plugin registers "0 features" / `gst-inspect mfvideosrc` says "no such element"; debug shows `MFStartup` → `0x80004001` (E_NOTIMPL) | The build image's **Server Core** base ships no Media Foundation platform — copying `mfplat.dll`/`mf.dll` doesn't help (the `Server-Media-Foundation` feature is *Removed* with no servicing source; `Install-WindowsFeature` fails `0x800f0916`) | **Not a build defect.** `gstmediafoundation.dll` compiles, links, and loads correctly; it only registers `mfvideosrc` on a **Windows client host** (Win10/11) where MF is present. Verify the webcam source on the host, never in-container (which also has no camera). The Rust capture path auto-falls back `mfvideosrc → ksvideosrc → autovideosrc`, so `ksvideosrc` covers hosts without MF. |
| CMake configure: `add_subdirectory ... .plugin_symlinks/kataglyphis_native_inference/windows which is not an existing directory` (only this one plugin) | `Fix-FlutterPluginSymlinks` (now `Repair-FlutterPluginSymlink`, the old name kept as an alias) used to **copy** each plugin dir into `.plugin_symlinks`; it now makes a junction first and copies only when that does not resolve. For `kataglyphis_native_inference` the recursive copy of its deep `native/AccelerANTgine/third_party/*` tree overruns the 260-char path limit and aborts before `windows\` is copied, leaving a broken junction. Since 2026-09-05 that tree is no longer inside the plugin — the inference core is a sibling submodule at `third_party/AccelerANTgine` and the plugin directory is 97 files — so a copy would no longer overrun; the junction stays regardless, as the cheaper and more robust option | Use a **junction** (`mklink /J`) rather than a copy for container-local workspaces — immune to MAX_PATH (the "copy avoids symlink access-denied" rationale only applies to bind-mounted paths). Clear stale `windows\flutter\ephemeral` + `.dart_tool` first: a broken junction from a prior run makes `flutter build --config-only` crash `PathExistsException` (errno 183, "already exists"). |
| App window flashes then exits on the host (~6 MB, no window title) | The native C++ plugin can't load its dependency `AccelerANTgine.dll` — the build leaves it in a `bin\` **subdirectory** of the runner, not beside the exe — and the VC++ runtime isn't bundled | Copy `runner\...\bin\AccelerANTgine.dll` next to the exe, and stage the VC++ redist CRT DLLs (`VC\Redist\MSVC\*\x64\*.CRT\*.dll`, or `msvcp140.dll`/`vcruntime140*.dll` from `System32`). A fully-initialized app is ~130 MB with a real window handle. `Start-Windows.ps1` / the MSIX layout should place `AccelerANTgine.dll` beside the exe. |

### Standard build

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\Build-Windows.ps1
```

`pwsh`, not `powershell`: every ANTfrastructure module declares
`#requires -Version 7.0`. GStreamer needs no PATH preamble — the image bakes
`PKG_CONFIG_PATH` and the runtime DLLs.

### Build with custom workspace

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\Build-Windows.ps1 -WorkspaceDir "C:\GitHub\OmniAccelerANT"
```

### Selected presets, no MSIX

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\Build-Windows.ps1 `
  -Configurations "clangcl-debug,clangcl-release" `
  -SkipMsixPackaging
```

`Build-Windows.ps1 -?` lists the rest. CI passes only `-SkipMsixPackaging`, so
that invocation is the parity run — see AGENTS.md § 5.

## Android

Stop stale Gradle daemons when builds act inconsistently:

```bash
cd android && ./gradlew --stop
./gradlew assembleRelease
```

Regenerate Android scaffolding if required:

```bash
flutter create --platforms=android .
```

## Raspberry Pi

Run camera pipelines on the host (outside Docker):

```bash
gst-launch-1.0 \
  libcamerasrc ! video/x-raw,width=640,height=360,format=NV12,interlace-mode=progressive ! \
  x264enc speed-preset=1 threads=1 byte-stream=true ! \
  h264parse ! \
  webrtcsink signaller::uri="ws://0.0.0.0:8444" name=ws meta="meta,name=gst-stream"
```

Rotate stream if camera orientation is inverted:

```bash
gst-launch-1.0 \
  libcamerasrc ! video/x-raw,width=640,height=360,format=NV12,interlace-mode=progressive ! \
  videoflip method=rotate-180 ! \
  x264enc speed-preset=1 threads=1 byte-stream=true ! \
  h264parse ! \
  webrtcsink signaller::uri="ws://0.0.0.0:8444" name=ws meta="meta,name=gst-stream"
```

## Web Build (WASM)

Build the web bindings the way the web lane does (`ci-container-run-web-linux.sh`).
`build-web` runs wasm-pack with `-Z build-std`, so it needs the **nightly**
toolchain with `rust-src` and the wasm target, and it writes `web/pkg/`, which is
generated and gitignored — a build without it loads and then hangs:

```bash
rustup toolchain install nightly --component rust-src --target wasm32-unknown-unknown
flutter_rust_bridge_codegen build-web --release --rust-root third_party/OxidANT
```

Run Flutter web with COOP/COEP headers:

```bash
flutter run \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp
```

## Image gaps and image-tag history

Both entries below are **fixed**. They are kept because each cost at least one
CI run to diagnose and each reappears looking like broken code rather than like
a broken image — if a symptom comes back, it is an image regression, and the
answer is to fix the image, not to restore the workaround. AGENTS.md § 4 (Pitfalls specific to this project) carries
the one-line version of each.

- **Six image gaps this repo used to work around are fixed in the image
  (2026-09-05); do not reintroduce the workarounds.** Each cost at least one run
  to diagnose, so the symptoms stay written down — if one reappears it is an
  image regression, not something to patch around again.
  `/opt/flutter/packages/flutter_tools/.dart_tool` was root-owned inside a
  **read-only overlay layer**, which a non-owner can neither empty nor rename
  (both were tried and refused); `flutter pub get` died with
  `package_config.json (OS Error: Permission denied, errno = 13)` and only a
  `--tmpfs …:rw,mode=1777` mount could mask it. `/opt/android-sdk` was fully
  populated but neither `ANDROID_HOME` nor `ANDROID_SDK_ROOT` was in the image
  ENV, so `flutter build apk` stopped with `[!] No Android SDK found` — and
  because CodeQL wraps the build in `database create --command=…`, that
  surfaced three steps later as `needs to be finalized`. `SCCACHE_DIR` and
  `CCACHE_DIR` pointed into the mounted checkout, which pollutes the tree and
  on a bind-mounted host drive simply fails (`Can't initialize ccache use:
  Failed to set permissions`). `RUSTUP_HOME` and `CARGO_HOME` were `root:root`
  against a uid-1001 container (`could not create temp file …: Permission
  denied`; a hardlink copy is not a fix either — `protected_hardlinks` refuses
  root-owned files, and the `cp -a` fallback nests the tree so Corrosion reads
  an empty `rustc --version` and fails with `invalid value '' for
  '--toolchain'`). The `:latest-cross` tag was single-platform (own entry
  below), and there was no Java SDK. What remains is
  `setup_compiler_cache`, which now only calls ANTfrastructure's `setup_sccache`:
  that points `RUSTC_WRAPPER` and both CMake compiler launchers at the
  **guarded** `sccache-launcher.sh`, which survives sccache's own fatal errors
  when a CMake `TryCompile` deletes the scratch directory under it.

- **A single-arch image tag looks exactly like broken code.** Until 2026-09-04
  `ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest-cross` was an amd64-only
  tag, so both matrix rows pulled the same digest and the arm64 row ran x86-64
  binaries on an `ubuntu-26.04-arm` runner:
  `` /usr/local/cargo/bin/rustc: 1: ELF: not found `` plus a corrosion
  `FindRust.cmake` error. Nothing in this repo could work around it. The tag is
  now a proper OCI index (amd64, arm64, riscv64), published as `:latest` since
  the hub's 2026-09-22 rename (`:latest-cross` is retired), and the symptom is gone —
  verified by the pulled digest matching the registry's index digest, and by
  both rows failing identically afterwards instead of differently.
  Two things that survive from that hunt: the architectures stay independent,
  because the failing arm64 row used to cancel x64 before it finished and hid
  whether the healthy lane was green — `fail-fast: false` on the matrix did
  that until 2026-09-24, when the rows became two workflows (`linux-x64.yml`,
  `linux-arm64.yml`) that cannot cancel each other; and a `Failed to pull`
  line in a log is usually GitHub **echoing the retry script's source**, not
  running it — it cost hours of chasing a pull that had in fact succeeded.

## Windows build-step traps and MSIX packaging

The rules these came from are in AGENTS.md § 5; the evidence is here.

`-SkipMsixPackaging` alone is exactly what the workflow passes; adding
`-Configurations` is a deliberate deviation, not the parity run. Verified
2026-09-06: 22/22 steps, process exit 0, `omni_accelerant.exe` and
`oxidant.dll` under
`build\windows\x64\runner\x64-ClangCL-Windows-Release\`, `AccelerANTgine.dll`
under `build\windows\x64\bin\`. That directory is never cleaned, so the
pre-rename `kataglyphis_inference_engine.exe`,
`kataglyphis_rustprojecttemplate.dll` and `CppInference.dll` still sit beside
them — compare timestamps, not presence, when checking a rename.

The Windows engine is Stevedore's, **not** Rancher Desktop's — Rancher only
serves Linux containers, and its `docker`/`nerdctl` shims are first on `PATH`,
so the full path above is load-bearing. **Run it in the container, not on the
host.** The host's `cmake` is Strawberry Perl's 3.29.2 out of
`C:\Strawberry\c\bin`, which shadows anything newer and fails
`cmake_minimum_required(VERSION 3.31.6)` at configure; the image carries 4.4.3
(CI log, 2026-09-25).

Two Windows-specific traps these steps carry:

- The format gate hands `dart format` the tracked file list
  (`Get-ProjectDartFiles`, 60 files), **not `.`**: `dart format .` recurses into
  `.git`, and the deeply nested vendored submodule gitdir exceeds Windows
  MAX_PATH, so the listing throws and the gate crashes before formatting
  anything.
- Docs generation does **not** use the SDK-bundled `dart doc`. The dartdoc 9.0.4
  the image carried at the time crashes on *any* Flutter app — a `_stripDocImports`
  RangeError while precaching the Flutter SDK's own `@docImport` comments
  (reproduced with a bare `flutter create`). The step `pub global activate
  dartdoc` (≥ 9.0.9, which fixes it) and runs that — 9.0.9 in the 2026-09-25 CI
  run. The image has since moved to Flutter 3.47.4, the same SDK whose bundled
  `dart doc` the Linux lane's `generate-docs.sh` runs without trouble.

**MSIX packaging.** `msix_config.build_windows` is `false` on purpose: this
script owns the build, and a second `flutter build windows` driven by msix
would only re-run — with a different generator — what the presets already
produced. (Until 2026-09-06 it also tripped over a `CMakeCache.txt` synced back
from the container-local build root — *"the current CMakeCache.txt directory …
is different than the directory … where it was created"*. ANTfrastructure's
`Sync-FastLocalArtifactsToHost` now excludes `CMakeCache.txt` and `CMakeFiles`
from the sync-back, so the host tree gets artifacts, not CMake state.) The
**MSIX Compatibility Layout** step exists because msix looks for
`build\windows\x64\runner\Release\`, while the build installs to
`runner\<preset>\`; it replaces that flat `Release\` with a copy of the first
preset built, on every run and in the host tree too (a copy kept from an older
build carried an ONNX Runtime the run never proved), and *MSIX Packaging* runs
the hub's G6 census over it before `msix:create`.
Both halves were broken until 2026-09-03 and nobody noticed, because CI passes
`-SkipMsixPackaging` — packaging is only exercised locally.

## The Windows CI lane and the `$GIT_DIR` limit

**The CI lane** ([`windows-x64.yml`](../../.github/workflows/windows-x64.yml))
is three ANTfrastructure actions, one hub script and GitHub's
`actions/upload-artifact`, nothing hand-rolled:
`prepare-windows-container-host` (long paths, short-path clone, data-root move,
disk check, GHCR login, pull), the hub's `windows/scripts/Invoke-Lint.ps1 -Path
scripts` (parse gate plus AST traps over this repo's own PowerShell, on the host
before the image pull), `run-in-windows-container`, `actions/upload-artifact`
and `upload-codeql-sarif`. (A second job, `ort-runner-suite`, is a plain
checkout plus `run-pester-suite` over `scripts/windows/tests`, with no
container.) Three consequences:

- It prunes `third_party/DocumANTation` from the recursive checkout.
  This repo's chains are OmniAccelerANT → AccelerANTgine → ANTfrastructure →
  DocumANTation → md2pdfLib → `third_party/{smile,awesome-beamer}` and the same
  tail via OxidANT, and every level adds another
  `.git/modules/<name>/` segment until git aborts with `fatal: '$GIT_DIR' too
  big` — git's own limit, not MAX_PATH, so no clone root is short enough.

  **Resolved on 2026-09-05.** Measured by the `gitdir:` string each gitfile
  carries, at each step of the way:

  | chain | before | after md2pdfLib | after ANTfrastructure |
  | --- | --- | --- | --- |
  | `ANTfrastructure` directly | 180 ok | 158 ok | 149 ok |
  | via `AccelerANTgine` | 230 **fatal** | 208 ok | 199 ok |
  | via `OxidANT` | 238 **fatal** | 216 **fatal** | 207 ok |

  Two directory renames did it, neither of them a repository rename:
  `md2pdfLib/presentation/template/latex/` → `md2pdfLib/third_party/` inside
  DocumANTation, and `external/Kataglyphis-DocumANTation` →
  `third_party/DocumANTation` inside ANTfrastructure. Each saved segment counts
  **twice**, once in the worktree path and once in the `gitdir` string, which is
  why 25 characters behaved like 50. The threshold sits between 208 and 216.

  Renaming the repositories on GitHub did **not** help here and was not meant
  to: a submodule's directory comes from its `path` entry, not from the repo
  name. DocumANTation is ANTfrastructure's LaTeX tooling and the Windows build
  never reads it.

  The numbers above were measured before `ExternalLib/` became `third_party/`.
  That move shortens the chain further, but **only in a fresh clone**: git names
  `.git/modules/<name>` after the `[submodule "<name>"]` header, and it keeps an
  existing module directory when a submodule is moved in place. So `.gitmodules`
  here reads `third_party/OxidANT` while the dev box's checkout's gitfile said,
  on 2026-09-05, `gitdir: ../../.git/modules/ExternalLib/Kataglyphis-RustProjectTemplate` — 23
  characters that CI, which always clones fresh, does not pay. Reproduce with
  `cat third_party/*/.git`. A local checkout is therefore the *worst* case; if it
  resolves, CI does too.
- `mount-source`/`mount-target` stay unset: the action already defaults to
  `D:\ws` → `C:\ws`, which is where the short-path clone put the tree. Setting
  them to `github.workspace` would mount the submodule-less checkout instead.
- Artifact paths — and the lint step's `working-directory` — are therefore
  **absolute under the short-path clone** (`steps.prep.outputs.workspace`),
  never relative to `github.workspace`. A
  relative path matches nothing there, and `if-no-files-found: error` would
  report that as a missing build. `upload-codeql-sarif` exists for the same
  reason: `hashFiles()` only sees inside `GITHUB_WORKSPACE`.

## Windows pieces deliberately not reused

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

## Android and cross-toolchain constraints

The rules are in AGENTS.md § 4; the measurements that produced them are here.

- **`--gcc-toolchain` is load-bearing here, and ANTfrastructure deleted the helper
  that set it.** `export_clang_gcc_toolchain_env` went away upstream on
  2026-09-05 (`e2c63f7b`), documented as dead: *"had no caller in the build […]
  nothing in the tree sets a bare `CC=clang`"*. Both statements are true of
  ANTfrastructure and false of this repo — `export_toolchain_env` set exactly that
  bare `CC=clang` and called the function. Upstream names
  `/usr/local/bin/clang-<arch>` as the replacement, because those wrappers bake
  `--gcc-toolchain` in themselves; **`:latest` ships none of them**
  (`ls /usr/local/bin | grep clang` is empty), so that branch is preferred but
  never taken today. Two runs differing only in this flag settle what it is
  worth:

  | `CC` | result |
  | --- | --- |
  | `clang`, no flag | `clang++: error: linker command failed with exit code 1` |
  | `clang --gcc-toolchain=/opt/gcc-16.2.0` | bundle + all four packages |

  Without it clang resolves libstdc++ against the system copy rather than the
  source-built GCC 16.2.0 the image provides. `export_toolchain_env` restores
  the flags through `gcc_toolchain_prefix()`, which upstream kept — do not
  hard-code `/opt/gcc-16.2.0`.

  The wider lesson for every ANTfrastructure bump: upstream reasons about its own
  tree when it removes something. "No caller" means no caller *there*.

- **The Android prebuilts are aarch64 now, and the lane's toolchain moved with
  them.** Until 2026-09-11 the image carried `ELF x86-64` GStreamer/ONNX
  Runtime/OpenCV under `/opt/android/` while the app builds `arm64-v8a`, so the
  link died on every archive with `incompatible with aarch64linux`. The image
  now ships only `arm64-v8a` (`libs/arm64-v8a`, `jni/abi-arm64-v8a`, and an
  aarch64 `libgstreamer-1.0.a` built by NDK r29), so the cause of that message is
  gone from the image, and the lane links. Until 2026-09-17 the workflow's
  single matrix row (x64) ran under CodeQL, which stopped the Gradle build at
  Kotlin compilation, several steps before the native link (next bullet, and
  the observed run below). Since then CI passes `--run-codeql false` and runs
  the plain `flutter build apk` — native link and the plugin's JVM test
  included — green on every completed run from 2026-09-18 on (36154744222 on
  2026-09-25: a 91.8 MB `app-release.apk`).
  `abiFilters "arm64-v8a"` in the native plugin's
  `android/build.gradle` stays — real phones, not the emulator.
  AGP 9.4.0 + Gradle 9.7.1 builds that against four constraints, all
  load-bearing:

  - **Built-in Kotlin, with a declared KGP for the version check — and CodeQL
    has a ceiling under it.** `android.builtInKotlin=true` and no
    `kotlin-android` plugin anywhere; AGP compiles Kotlin itself, and the target
    is set with `kotlin { compilerOptions { jvmTarget = … } }`. AGP bundles KGP
    2.2.10, below Flutter's 2.2.20 floor, so `android/settings.gradle.kts` must
    keep `id("org.jetbrains.kotlin.android") version "2.4.20" apply false` — the
    declaration, not an application, is what raises the classpath KGP. Remove it
    and Flutter stops with `Your project's Kotlin version (2.2.10) is lower than
    Flutter's minimum supported version of 2.2.20`.

    The floor has a ceiling above it that belongs to a different tool. CodeQL's
    Java extractor injects a Kotlin compiler plugin, and that plugin's upper
    bound sits **below** the KGP this repo declares, so asking for a java
    database killed the whole Gradle build rather than just the scan — observed
    state, run 34870931651 (2026-09-14), task
    `:kataglyphis_native_inference:compileReleaseKotlin`:
    `Kotlin version 2.4.20 is too recent. CodeQL currently supports versions
    below 2.4.20`, after which `database create` reported `Exit status 1 from
    command: [/tmp/codeql-build.sh]` and the lane exited 2 with no APK.
    The two bounds cannot both be satisfied by one KGP *and* a java database:
    Flutter wants ≥ 2.2.20, CodeQL wants < 2.4.20, and 2.4.20 is what is
    declared. `scripts/linux/codeql/codeql-android.sh` therefore builds the
    cluster for **cpp, c and rust only** — where this project's inference code
    actually is — and `codeql_analyze_java` is kept, callerless, in
    `codeql-common.sh` for the day the ceiling clears. Do not "fix" the missing
    java rows by lowering the KGP: that trades a building app for a scan of five
    glue files.
  - **`android.newDsl=false` stays.** The Flutter Gradle plugin still needs the
    legacy DSL types, AGP 9.4 marks them deprecated, and Gradle 9.7's Kotlin-DSL
    script compilation turns that into `Script compilation errors`. That is why
    `android/app/build.gradle.kts` opens with
    `@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")`.
  - **Cargokit carries a Gradle 9 port.** `Project.exec` and `Project.buildDir`
    are gone in Gradle 9; `rust_builder/cargokit/gradle/plugin.gradle` injects
    `ExecOperations` and reads `project.layout.buildDirectory`. Upstream Cargokit
    still has the old calls, so keep this patch when bumping the vendored copy.
  - **`permission_handler_android` is pinned to 13.0.1** in
    `pubspec_overrides.yaml`. The 14.x that permission_handler 13.0.2 resolves
    needs `compileSdk 37`; the image ships android-36 and its SDK is read-only.
    Drop the pin when the image carries 37.
