# Platform Guides

Build and run instructions by target platform.

## Container Setup (Linux/WSL)

Run a command in the family Linux CI image through ANTfrastructure's driver, not an engine
line. It owns the image reference, the bind mount at `/workspace` and the `safe.directory` that
mount needs, picks `nerdctl` or `docker`, and sets the `MSYS_NO_PATHCONV` a Git Bash caller needs:

```bash
bash third_party/ANTfrastructure/linux/scripts/run-in-ci-image.sh . -- flutter --version
```

The **Stream demo** needs three things the driver deliberately does not expose (an interactive
TTY, published ports, a `--device` passthrough), so it is a direct engine call. Its image
reference is still not typed: `ci-image-ref.sh`, which the driver calls too, composes it from the
hub's `versions.env`, the family's one owner of both CI image refs.

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

For WSL2 camera passthrough, attach the USB device before starting the container.

## Windows Development

### Containerized build (Stevedore, recommended)

Windows builds run in the `kataglyphis_beschleuniger:winamd64` image from
[ANTfrastructure](https://github.com/Kataglyphis/ANTfrastructure), the one CI uses, on
[Stevedore](https://github.com/slonopotamus/stevedore) (`winget install stevedore`). Set the host
up with ANTfrastructure's `docs/windows-host-setup.md` (Phase A), apply the post-install fixes in
its `docs/windows-stevedore-and-docker.md` (§ Stevedore Setup Fixes), and always call Stevedore's
bundled `docker.exe`, never `nerdctl`:

```powershell
$docker = "$env:ProgramFiles\Stevedore\bin\docker.exe"
& $docker pull ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64
```

Run the build container with **process isolation** (`--isolation process`): it gets the host's
full CPU count instead of the Hyper-V default's 2. Never pass it to `docker build`. The engine
rationale, the CPU/base-build caps and the `docker build` prohibition are ANTfrastructure's:
[`windows-build-lanes.md`](../../third_party/ANTfrastructure/docs/windows-build-lanes.md).

```powershell
& $docker run --rm --isolation process `
  --mount "type=bind,source=$PWD,target=C:\ws-mnt" -w C:\ws-mnt `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64 `
  pwsh -NoProfile -ExecutionPolicy Bypass -File C:\ws-mnt\scripts\windows\Build-Windows.ps1 `
    -Configurations "clangcl-debug,clangcl-profile,clangcl-release" -SkipMsixPackaging
```

`-Configurations` takes preset aliases: `clangcl-debug`, `clangcl-profile`, `clangcl-release` map
to the `x64-ClangCL-Windows-{Debug,Profile,Release}` CMake presets; also `msvc-*`, `clang-*`
(full list: § *The Windows lanes in detail*).

> **The bind-mount traps are the hub's**: a Dev Drive refuses the mount until its filters are
> allowed ([`windows-container-build-performance.md` § *Transport B*](../../third_party/ANTfrastructure/docs/windows-container-build-performance.md#transport-b--bind-mount-dev-drive-needs-setup)),
> and on this host's version skew Dart's `copySync`/`renameSync` fail on a mounted path, a
> target the image holds fails at `hcs::CreateComputeSystem`, and `docker cp` copies nothing
> ([`windows-build-lanes.md` § *Run-side wcifs symptoms*](../../third_party/ANTfrastructure/docs/windows-build-lanes.md#run-side-wcifs-symptoms-process-isolation)).
> This repo's half:
>
> - **Not admin on a Dev Drive:** mirror the repo to a plain NTFS path on `C:` and mount that:
>
>   ```powershell
>   robocopy D:\GitHub\OmniAccelerANT C:\kata-ws /E /MT:16 /XJ /XD .dart_tool build logs
>   & $docker run --rm --isolation process `
>     --mount "type=bind,source=C:\kata-ws,target=C:\ws-mnt" -w C:\ws-mnt `
>     ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64 `
>     pwsh -NoProfile -ExecutionPolicy Bypass -File C:\ws-mnt\scripts\windows\Build-Windows.ps1 `
>       -Configurations "clangcl-debug,clangcl-profile,clangcl-release" -SkipMsixPackaging
>   ```
>
> - **Junction the Dart write dirs** to container-local paths from inside a long-lived
>   container before building, the plugin's pair too: its tests copy into
>   `packages\kataglyphis_native_inference\build\unit_test_assets` (measured 2026-10-05).
>   `mklink /J` refuses an existing directory, so move the host's four aside first, and `rmdir`
>   the junctions before the container exits, or the host keeps four junctions to paths only
>   the container had:
>
>   ```powershell
>   docker exec <name> cmd /c "mkdir C:\dtool & mkdir C:\fbuild\native_assets\windows & mkdir C:\pdtool & mkdir C:\pbuild & mklink /J C:\ws-mnt\.dart_tool C:\dtool & mklink /J C:\ws-mnt\build C:\fbuild & mklink /J C:\ws-mnt\packages\kataglyphis_native_inference\.dart_tool C:\pdtool & mklink /J C:\ws-mnt\packages\kataglyphis_native_inference\build C:\pbuild"
>   ```
>
> - **Mount at a fresh target, `C:\ws-mnt`**; CI mounts `D:\ws → C:\ws`. With no mount at all,
>   `scripts/windows/Build-Windows-Container.ps1` streams the sources into a reused container.

> **ANTfrastructure submodule:** `scripts/windows/Build-Windows.ps1` resolves every PowerShell
> module through `scripts/windows/Resolve-BuildModule.ps1`:
> `third_party/ANTfrastructure/windows/scripts/modules/` first, then `scripts/windows/modules/`.
> Check the submodule out before building
> (`git submodule update --init --recursive third_party/ANTfrastructure`); a missing one is
> reported by name with that exact command. Every module declares `#requires -Version 7.0`, hence
> `pwsh`, never `powershell`, in every command here.

Run the app on the host after a build:

```powershell
.\scripts\windows\Start-Windows.ps1                                        # runner\Release: the MSIX copy of the first preset built
.\scripts\windows\Start-Windows.ps1 -Configuration x64-ClangCL-Windows-Debug
```

### Troubleshooting containerized Windows builds

| Symptom | Cause | Fix |
|---------|-------|-----|
| CMake: `Could NOT find PkgConfig` | The winamd64 image bakes `PKG_CONFIG_PATH` + `.pc` files (`C:\runtime\...`); older builds of it shipped **no pkg-config binary**. Fixed in the image: its `Install-ScoopTools.ps1` installs pkg-config (hub `docs/windows-builds.md` § *Toolchain pins and the provenance manifest*) | Pull a current `:winamd64`; a reappearance is an image regression. On an old image: `scoop install pkg-config` in the container (there is no `pkgconf` manifest). |
| Cargokit: `rustup not found in PATH.` during CMake install | The Flutter plugin `rust_builder` builds its Rust crate via Cargokit, which hard-requires rustup; older image builds were scoop-Rust-only. Fixed in the image: `Install-RustToolchain.ps1` provisions rustup with a default toolchain (hub `docs/windows-builds.md` § *Rust toolchain*) | Pull a current `:winamd64`. On an old image, in the container: `Invoke-WebRequest https://win.rustup.rs/x86_64 -OutFile C:\rustup-init.exe; C:\rustup-init.exe -y --default-toolchain stable --profile minimal`. A rustup **with** a default toolchain is safe; ANTfrastructure's warning targets toolchain-less rustup shims only. |
| `PathNotFoundException ... sqlite3.dll.tmp` in `flutter assemble` | Dart's `renameSync`/`copySync` fail (errno 3) in container-layer dirs **and on bind-mounted paths** on this skewed host: the sqlite3 hook downloads fine, then dies on the two-path file op | Junction `.dart_tool` and `build` to fresh **container-local** dirs (`mklink /J`, from inside the container), where Dart ops work. Fallback if junctions are impossible: patch the hook (`renameSync` → direct `openWrite` to the final name). |
| `lld-link ... mismatch detected for 'RuntimeLibrary'` (Debug preset) | A `/MT` override (root `CMAKE_MSVC_RUNTIME_LIBRARY`, an abseil `/MT` hack, or a C++20 module BMI built `/MT` re-emitting `detect_mismatch` into importers) collides with Flutter's `/MD` | Remove **every** `/MT` override and compile ASAN with `/clang:-shared-libsan` so clang emits dynamic-CRT link directives. Wired up in the upstream module `third_party/ANTfrastructure/cmake/Sanitizers.cmake`, reached via `CMAKE_MODULE_PATH` (the inference core's own copy is retired), plus the no-`/MT` policy in `third_party/AccelerANTgine/third_party/CMakeLists.txt`. Diagnose stray directives with `llvm-readobj --coff-directives <obj>`. |
| Instrumented app dies instantly `STATUS_ENTRYPOINT_NOT_FOUND` (−1073741511) | The staged `clang_rt.asan_dynamic-x86_64.dll` is LLVM's, but the binary's baked-in thunk imports Microsoft-named allocator forwarders (`__asan_new`, `__asan_delete`, …), or vice-versa | Link **and** stage a matched pair. The Debug preset links Microsoft's thunk+import lib (ANTfrastructure's `cmake/Sanitizers.cmake`, on `CMAKE_MODULE_PATH`, points the link-search at `VC\Tools\MSVC\<ver>\lib\x64`); `Start-Windows.ps1` stages the matching `clang_rt.asan_dynamic-x86_64.dll` from the same MSVC dir. |
| Instrumented app aborts on startup with `bad-free` / `bad-malloc_usable_size` | LLVM's ASan runtime loads after ucrtbase, so CRT/COM startup allocations are unhooked and abort when freed through interceptors | Use **Microsoft's** ASan runtime (VS BuildTools), which tracks Windows heap ownership and passes foreign frees through, plus `ASAN_OPTIONS=alloc_dealloc_mismatch=0:check_malloc_usable_size=0`. This is the shipped Debug-preset config; the full app runs clean under it. |
| App exits with `STATUS_DLL_NOT_FOUND` (−1073741515) on a host without GStreamer/ONNX installs | The native plugin links GStreamer + ONNX Runtime: `C:\runtime` in the container, `C:\Program Files\gstreamer` + `C:\onnxruntime` on a provisioned host | Stage from the image into the runner: `C:\runtime\bin\*.dll` except `onnxruntime*.dll`/`DirectML.dll` → `runner\...\bin\` (ONNX Runtime is already beside the exe: `Build-Windows.ps1` stages the chain copy and `Start-Windows.ps1` refuses any other, AGENTS.md § 4); `C:\runtime\lib\gstreamer-1.0\` → `runner\...\lib\gstreamer-1.0\` (GStreamer finds plugins relative to its core DLL). `Start-Windows.ps1` puts `runner\bin` on `PATH`. With the Rust `gstreamer` feature on (the Windows default) the build's *Bundle Media Runtime DLLs* step already copies `C:\runtime\bin\*.dll` (ORT family excluded) beside the exe and ten capture plugins into `gstreamer-1.0\`. |
| `git init/clone/checkout` fails with `could not write config file` / `unable to write new index file` inside the container | Same `wcifs` rename/create flakiness in layer dirs | Do git surgery outside the layer zone (fresh `C:\` dirs work), or `git archive | tar -x` trees into place; a bind-mounted workspace avoids it entirely. |
| `docker run --mount` fails: `hcs::CreateComputeSystem ... Die Anforderung wird nicht unterstützt` although the source is plain NTFS | The mount **target** already exists in the image (`C:\workspace` before 2026-09-26), refused on skewed hosts | Mount to a path the image lacks (e.g. `target=C:\ws-mnt`) and pass `-w C:\ws-mnt`. |
| `docker commit` (or `docker start` of a stopped container) fails `hcsshim::ActivateLayer ... (0x20)` | The container was created with `--isolation process`; on this host its writable layer stays locked after stop and cannot be snapshotted | Create any container you will **commit** with `--isolation hyperv` (kept alive + `docker exec` build + stop + commit works; that is why the ANTfrastructure orchestrator uses hyperv for run+commit). `docker export` is **not** a workaround (the daemon refuses to export Windows containers). Keep `--isolation process` for throwaway runs whose output you extract *live* via `tar` over `docker exec` before stopping. |
| `mediafoundation` plugin registers "0 features" / `gst-inspect mfvideosrc` says "no such element"; debug shows `MFStartup` → `0x80004001` (E_NOTIMPL) | The build image's **Server Core** base ships no Media Foundation platform; copying `mfplat.dll`/`mf.dll` does not help (the `Server-Media-Foundation` feature is *Removed* with no servicing source; `Install-WindowsFeature` fails `0x800f0916`) | **Not a build defect.** `gstmediafoundation.dll` compiles, links and loads; it registers `mfvideosrc` only on a **Windows client host** (Win10/11), where MF is present. Verify the webcam source on the host, never in the container (which has no camera either). The Rust capture path falls back `mfvideosrc → ksvideosrc → autovideosrc`, so `ksvideosrc` covers hosts without MF. |
| CMake configure: `add_subdirectory ... .plugin_symlinks/kataglyphis_native_inference/windows which is not an existing directory` (only this one plugin) | `Fix-FlutterPluginSymlinks` (now `Repair-FlutterPluginSymlink`, the old name kept as an alias) used to **copy** each plugin dir into `.plugin_symlinks`; it now makes a junction first and copies only when that does not resolve. For `kataglyphis_native_inference` the recursive copy of its deep `native/AccelerANTgine/third_party/*` tree overran the 260-char path limit and aborted before `windows\` was copied, leaving a broken junction. Since 2026-09-05 the inference core is a sibling submodule at `third_party/AccelerANTgine` and the plugin directory is about 100 files, so a copy would no longer overrun; the junction stays as the cheaper, more robust option | Use a **junction** (`mklink /J`), not a copy, for container-local workspaces: immune to MAX_PATH (the "copy avoids symlink access-denied" rationale applies only to bind-mounted paths). Clear stale `windows\flutter\ephemeral` + `.dart_tool` first: a broken junction from a prior run makes `flutter build --config-only` crash `PathExistsException` (errno 183, "already exists"). |
| App window flashes then exits on the host (~6 MB, no window title) | The native C++ plugin cannot load its dependency `AccelerANTgine.dll`. Before 2026-10-17 the x64 build left it, the VC++ runtime and a second ORT in a `bin\` **subdirectory** of the runner, where the loader never looks, so the released zip started only with `bin\` on `PATH` | Fixed at the source: the plugin's `CMakeLists.txt` sets `CMAKE_INSTALL_BINDIR` and `CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION` to `.` before it embeds AccelerANTgine, so both land beside the exe, as on arm64. The x64 launch smoke starts the runner without any `-SearchPath`, as a double-click does. A runner that still has a `bin\` is from an older build: rebuild. A fully initialized app is ~130 MB with a real window handle. |

### Tar-pipe inbound exclusions

`Build-Windows-Container.ps1` streams the checkout into the reused container with bsdtar, which
aborts the **whole** archive on any entry it cannot stat. Two such entries stay excluded: the host's
Flutter plugin junctions under `ephemeral/` (the container regenerates them) and the Linux symlinks
the cargo-cache sync-back leaves in `third_party/OxidANT/target` (the container builds into its own
`CARGO_TARGET_DIR` instead).

- Patterns match whole path components **at every depth**, and no form anchors (`./build`,
  `[.]/build` and `build/` all behave the same), so a root directory cannot be excluded by name:
  `build` would also take `third_party/ANTfrastructure/windows/scripts/build`. Root directories are
  omitted from the item list instead (`-InboundItems`, computed in the driver); the patterns cover
  the deep directories.
- No pattern is a prefix glob like `out*`, which would drop unrelated directories such as
  nlohmann's `detail/output/`.
- Of `.git` only `modules/` and the object store are left out: the CMake format gate's
  `git ls-files` needs HEAD, the index and refs, never an object.

### Standard build

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\Build-Windows.ps1
```

`pwsh`, not `powershell` (the submodule note above). GStreamer needs no PATH preamble: the image
bakes `PKG_CONFIG_PATH` and the runtime DLLs.

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

`Build-Windows.ps1 -?` lists the rest. CI's Release job (`build-clang`) passes only
`-SkipMsixPackaging`, so that invocation is the parity run (AGENTS.md § 5); its Debug job adds
`-Configurations clangcl-debug -SkipFormat -SkipDocs`.

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

The app's Pi producer and its runbook: [camera-streaming.md](camera-streaming.md)
§ *Cat detection stream (Rust, native)*. Raw `gst-launch-1.0` pipelines from a Pi camera to
`webrtcsink`, for debugging below the app:
[`runtime-services.md` § *Raw `gst-launch-1.0` pipelines*](../../third_party/ANTfrastructure/docs/runtime-services.md#raw-gst-launch-10-pipelines-debugging-below-the-app).
An inverted camera takes `videoflip method=rotate-180 !` after the caps filter.

## Web Build (WASM)

Build the web bindings as the web lane does (`ci-container-run-web-linux.sh`). `build-web` runs
wasm-pack with `-Z build-std`, so it needs the **nightly** toolchain with `rust-src` and the wasm
target. It writes `web/pkg/` (generated, gitignored); a build without it waits 20 s for the core at
start-up, then runs without it (only the About page's Rust demo needs it):

```bash
# The image's dated nightly, as the lane takes it; the floating one breaks in :latest (AGENTS.md § 4).
nightly="$(sed -n 's/^RUST_NIGHTLY_TOOLCHAIN=//p' third_party/ANTfrastructure/linux/scripts/01-core/versions.env)"
rustup toolchain install "$nightly" --component rust-src --target wasm32-unknown-unknown
flutter_rust_bridge_codegen build-web --release --rust-root third_party/OxidANT \
  --wasm-pack-rustup-toolchain "$nightly"
```

Run Flutter web with COOP/COEP headers: Firefox and Safari load the core's shared-memory wasm only
on a cross-origin isolated page:

```bash
flutter run \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp
```

## Image gaps and image-tag history

Both entries are **fixed**, and kept because each cost at least one CI run to diagnose and
reappears looking like broken code, not like a broken image. A returning symptom is an image
regression: fix the image, never restore the workaround. AGENTS.md § 4 (Pitfalls specific to this
project) carries the one-line version of each.

- **Six image gaps this repo used to work around are fixed in the image (2026-09-05); do not
  reintroduce the workarounds.**
  1. `/opt/flutter/packages/flutter_tools/.dart_tool` was root-owned inside a **read-only
     overlay layer**, which a non-owner can neither empty nor rename (both tried, both refused);
     `flutter pub get` died with `package_config.json (OS Error: Permission denied, errno = 13)`
     and only a `--tmpfs …:rw,mode=1777` mount could mask it.
  2. `/opt/android-sdk` was fully populated but neither `ANDROID_HOME` nor `ANDROID_SDK_ROOT` was
     in the image ENV, so `flutter build apk` stopped with `[!] No Android SDK found`; because
     CodeQL wraps the build in `database create --command=…`, that surfaced three steps later as
     `needs to be finalized`.
  3. `SCCACHE_DIR` and `CCACHE_DIR` pointed into the mounted checkout, which pollutes the tree
     and on a bind-mounted host drive fails
     (`Can't initialize ccache use: Failed to set permissions`).
  4. `RUSTUP_HOME` and `CARGO_HOME` were `root:root` against a uid-1001 container
     (`could not create temp file …: Permission denied`). A hardlink copy is no fix either:
     `protected_hardlinks` refuses root-owned files, and the `cp -a` fallback nests the tree, so
     Corrosion reads an empty `rustc --version` and fails with
     `invalid value '' for '--toolchain'`.
  5. The `:latest-cross` tag was single-platform (next entry).
  6. There was no Java SDK.

  What remains is `setup_compiler_cache`, now only a call to ANTfrastructure's `setup_sccache`. It
  points `RUSTC_WRAPPER` and both CMake compiler launchers at the **guarded**
  `sccache-launcher.sh`, which survives sccache's own fatal errors when a CMake `TryCompile`
  deletes the scratch directory under it. Those `TryCompile`s are also the 63 C/C++ misses in the
  native lane's sccache stats on every run: the launchers are environment variables, so configure
  checks go through sccache too, each in a randomly named `CMakeScratch/TryCompile-*` directory no
  later run repeats. AccelerANTgine configured twice in `:latest` missed 21 of 32 such compiles
  the second time (2026-10-16); the lane configures three times (release, the integration test's
  debug, the performance test's profile). Every real source hits and the checks are tiny; raising
  `SCCACHE_CACHE_SIZE` changed nothing (d8044b1, reverted in 7badf5f).

- **A single-arch image tag looks exactly like broken code.** Until 2026-09-04
  `ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest-cross` was amd64-only, so both matrix rows
  pulled the same digest and the arm64 row ran x86-64 binaries on an `ubuntu-26.04-arm` runner:
  `` /usr/local/cargo/bin/rustc: 1: ELF: not found `` plus a corrosion `FindRust.cmake` error.
  Nothing in this repo could work around it. The tag is now a proper OCI index (amd64, arm64,
  riscv64), published as `:latest` since the hub's 2026-09-22 rename (`:latest-cross` is retired).
  Verified by the pulled digest matching the registry's index digest, and by both rows then
  failing identically instead of differently. Two lessons survive the hunt:
  - The architectures stay independent: the failing arm64 row used to cancel x64 before it
    finished and hid whether the healthy lane was green. `fail-fast: false` on the matrix did that
    until 2026-09-24, when the rows became two workflows (`linux-x64.yml`, `linux-arm64.yml`) that
    cannot cancel each other.
  - A `Failed to pull` line in a log is usually GitHub **echoing the retry script's source**, not
    running it; it cost hours chasing a pull that had in fact succeeded.

## Windows build-step traps and MSIX packaging

The rules these came from are in AGENTS.md § 5; the evidence is here.

**The parity run is `-SkipMsixPackaging` alone**, exactly what the workflow passes; adding
`-Configurations` deviates on purpose. Verified 2026-09-06: 22/22 steps, process exit 0,
`omni_accelerant.exe` and `oxidant.dll` under
`build\windows\x64\runner\x64-ClangCL-Windows-Release\`, `AccelerANTgine.dll` under
`build\windows\x64\bin\`. That directory is never cleaned, so the pre-rename
`kataglyphis_inference_engine.exe`, `kataglyphis_rustprojecttemplate.dll` and `CppInference.dll`
still sit beside them: compare timestamps, not presence, when checking a rename.

**The Windows engine is Stevedore's, not Rancher Desktop's.** Rancher serves only Linux
containers and its `docker`/`nerdctl` shims come first on `PATH`, so Stevedore's full
`docker.exe` path is load-bearing. **Run it in the container, not on the host.** The host's
`cmake` is Strawberry Perl's 3.29.2 out of `C:\Strawberry\c\bin`, which shadows anything newer and
fails `cmake_minimum_required(VERSION 3.31.6)` at configure; the image carries 4.4.3 (CI log,
2026-09-25).

Two Windows-specific traps these steps carry:

- The format gate hands `dart format` the tracked file list (`Get-ProjectDartFiles`, the list of
  AGENTS.md § 4; 85 files on 2026-10-14), **not `.`**: `dart format .` recurses into `.git`,
  the deeply nested vendored submodule gitdir exceeds Windows MAX_PATH, and the listing throws,
  so the gate crashes before formatting anything.
- Docs generation does **not** use the SDK-bundled `dart doc`: the dartdoc 9.0.4 the image
  carried at the time crashes on *any* Flutter app, a `_stripDocImports` RangeError while
  precaching the Flutter SDK's own `@docImport` comments (reproduced with a bare
  `flutter create`). The step runs `pub global activate dartdoc` (≥ 9.0.9, which fixes it) and
  uses that; 9.0.9 in the 2026-09-25 CI run. The image has moved on since (the hub pins Flutter
  3.47.7 today), and the Linux lane's `generate-docs.sh` runs its bundled `dart doc` fine.

**MSIX packaging.** `msix_config.build_windows` is `false` on purpose: this script owns the
build, and a second `flutter build windows` driven by msix would only re-run, with a different
generator, what the presets already produced. (Until 2026-09-06 it also tripped over a
`CMakeCache.txt` synced back from the container-local build root: *"the current CMakeCache.txt
directory … is different than the directory … where it was created"*. ANTfrastructure's
`Sync-FastLocalArtifactsToHost` now excludes `CMakeCache.txt` and `CMakeFiles` from the
sync-back, so the host tree gets artifacts, not CMake state.)

The **MSIX Compatibility Layout** step exists because msix looks for
`build\windows\x64\runner\Release\` while the build installs to `runner\<preset>\`. It replaces
that flat `Release\` with a copy of the first preset built, on every run and in the host tree too
(a copy kept from an older build carried an ONNX Runtime the run never proved), and *MSIX
Packaging* runs the hub's G6 census over it before `msix:create`. Both halves were broken until
2026-09-03 and nobody noticed, because CI passes `-SkipMsixPackaging`: packaging runs only
locally.

### `-ftime-trace` stays on, though nothing reads the traces

`Build-Windows.ps1` passes `-DKATAGLYPHIS_ENABLE_TIME_TRACE=ON` and CMake's configure profile
to every configure; no step or workflow reads either. It looks like dead weight that costs speed:
sccache cannot cache a compile with `-ftime-trace` (run 38711050047's Debug build:
`Non-cacheable reasons: -ftime-trace 279`, all its C++ units). But that is what keeps a reused
container safe: the image's sccache 0.18 with clang-cl hashes a C++23 module importer without the
BMIs it imports, so after an interface edit a warm cache hands back the old object (hub
`docs/windows-container-build-performance.md` § *sccache on a C++23 modules build*). Take the flag
out only once the image's sccache carries mozilla/sccache#2876, or with sccache off for the C++
units.

## The Windows CI lane and the `$GIT_DIR` limit

**The CI lane** ([`windows-x64.yml`](../../.github/workflows/windows-x64.yml)) is three
ANTfrastructure actions, one hub script and GitHub's `actions/upload-artifact`:

- `prepare-windows-container-host`: long paths, short-path clone, data-root move, disk check,
  GHCR login, pull.
- The hub's `windows/scripts/Invoke-Lint.ps1 -Path scripts`: parse gate plus AST traps over this
  repo's own PowerShell, on the host before the ~54 GB image pull.
- `run-in-windows-container`, `actions/upload-artifact` and `upload-codeql-sarif`.
- After the upload, four host steps test the runner outside the image, as the arm64 lane does:
  this repo's `Test-KntAbi.ps1` and `Invoke-PluginGTest.ps1` (the plugin's gtest, built in the
  image, where `flutter_windows.dll` does not load), the hub's
  `Test-TargetArch.ps1 -ImportWalk -Standalone`, and `Test-LaunchSmoke.ps1 -OrtStamp`, which
  re-proves the G6 stamp before it starts the app.

CI passes `-SkipMsixPackaging`, and `-CodeQL` is off there because of runtimes. The workflow has
two more jobs:

- `build-clang-debug` runs `Build-WindowsDebugApps.ps1` in one container (since 2026-10-15): the
  `clangcl-debug` preset (ASan + UBSan), copied to `…-Debug-app`, then the same preset with
  `-FlutterTarget integration_test/simple_test.dart` on the first build's tree, where a container
  of its own rebuilt all 520 targets (11:45 of 14.9 min). Both carry Microsoft's ASan runtime
  (`Stage-AsanRuntime.ps1`), as `Start-Windows.ps1` stages it locally. The launch smoke runs the
  `…-Debug-app` copy; `Invoke-WindowsIntegrationTest.ps1` drives the integration twin, which stays
  at `…-Debug`. The Release job keeps the lane's quality gates.
- `ort-runner-suite` is a plain checkout plus `run-pester-suite` over `scripts/windows/tests`,
  with no container.

Three consequences, each easy to undo by accident:

- It prunes `third_party/DocumANTation` from the recursive checkout. This repo's chains are
  OmniAccelerANT → AccelerANTgine → ANTfrastructure → DocumANTation → md2pdfLib →
  `third_party/{smile,awesome-beamer}`, and the same tail via OxidANT; every level adds another
  `.git/modules/<name>/` segment until git aborts with `fatal: '$GIT_DIR' too big`: git's own
  limit, not MAX_PATH, so no clone root is short enough.

  **Resolved on 2026-09-05.** Measured by the `gitdir:` string each gitfile carries, at each
  step:

  | chain | before | after md2pdfLib | after ANTfrastructure |
  | --- | --- | --- | --- |
  | `ANTfrastructure` directly | 180 ok | 158 ok | 149 ok |
  | via `AccelerANTgine` | 230 **fatal** | 208 ok | 199 ok |
  | via `OxidANT` | 238 **fatal** | 216 **fatal** | 207 ok |

  Two directory renames did it, neither a repository rename:
  `md2pdfLib/presentation/template/latex/` → `md2pdfLib/third_party/` inside DocumANTation, and
  `external/Kataglyphis-DocumANTation` → `third_party/DocumANTation` inside ANTfrastructure. Each
  saved segment counts **twice**, in the worktree path and in the `gitdir` string, which is why
  25 characters behaved like 50. The threshold sits between 208 and 216.

  Renaming the repositories on GitHub did **not** help and was not meant to: a submodule's
  directory comes from its `path` entry, not from the repo name. DocumANTation is
  ANTfrastructure's LaTeX tooling; the Windows build never reads it.

  The numbers predate `ExternalLib/` becoming `third_party/`. That move shortens the chain
  further, but **only in a fresh clone**: git names `.git/modules/<name>` after the
  `[submodule "<name>"]` header and keeps an existing module directory when a submodule is moved
  in place. So `.gitmodules` here reads `third_party/OxidANT` while the dev box's gitfile said, on
  2026-09-05, `gitdir: ../../.git/modules/ExternalLib/Kataglyphis-RustProjectTemplate`: 23
  characters that CI, which always clones fresh, does not pay. Reproduce with
  `cat third_party/*/.git`. A local checkout is therefore the *worst* case; if it resolves, CI
  does too.
- `mount-source`/`mount-target` stay unset: the action already defaults to `D:\ws` → `C:\ws`,
  where the short-path clone put the tree. Setting them to `github.workspace` would mount the
  submodule-less checkout instead.
- Artifact paths, and the lint step's `working-directory`, are therefore **absolute under the
  short-path clone** (`steps.prep.outputs.workspace`), never relative to `github.workspace`. A
  relative path matches nothing there, and `if-no-files-found: error` would report that as a
  missing build. `upload-codeql-sarif` exists for the same reason: `hashFiles()` only sees inside
  `GITHUB_WORKSPACE`.

## The app's Windows installers

Since 2026-10-17 every release carries the app as an MSI and a signed MSIX for x64 and arm64,
beside the zip. `scripts/windows/Package-OmniAccelerANT.ps1` makes both from the runner folder;
`scripts/windows/modules/WindowsAppInstallers.Common.psm1` (`New-AppMsi`, `New-AppMsix`) holds
the part ObservANT's packaging shares.

- **Built where the app is**: the x64 lane's `build-clang` job on the `windows-2025` host and the
  arm64 lane's `app` job on `windows-11-arm`. Each installs WiX 7.0.0 (the image's pin) as a
  dotnet tool and uses the runner's Windows SDK for `makeappx` and `signtool`. Neither runner
  image ships a .NET SDK, so `actions/setup-dotnet` installs 10.0 first; WiX 7 is a net8.0 tool
  that rolls forward to it.
- **First proof, 2.1.0 on develop** (runs 39038477716 and 39038479571): x64 MSI 46 MB and MSIX
  54 MB, arm64 MSI 34 MB and MSIX 41 MB, all twelve installer checks passing on both.
- **The MSI** (`scripts/windows/installer/omni-accelerant.wxs`) installs per machine into
  `Program Files\OmniAccelerANT` with a Start menu shortcut, and upgrades in place (one
  `UpgradeCode`). Its version is `pubspec.yaml`'s `version:`.
- **The MSIX** (`scripts/windows/installer/AppxManifest.xml`) has the identity
  `Kataglyphis.OmniAccelerANT` and the `msix_version` of `msix_config`. A throwaway test
  certificate signs it; its `-testcert.cer` ships beside it, and a tester trusts that `.cer` under
  `LocalMachine\TrustedPeople` before installing.
- **`Test-OmniAccelerANTInstallers.ps1`** installs the MSI with `msiexec /qn` and checks that
  `AccelerANTgine.dll` sits beside the exe with no `bin\`, that the exe, the plugin and
  AccelerANTgine.dll match the lane's architecture, and that the Start menu shortcut exists. It
  then starts the installed app through `Test-LaunchSmoke.ps1` without any `-SearchPath`, as the
  shortcut does. For the MSIX it checks signature, identity and architecture, trusts the
  certificate, runs `Add-AppxPackage`, starts the package through its app entry and removes it.
- **A runner with a `bin\` folder is refused** by the packaging script: before 9f4438e the x64
  build left AccelerANTgine.dll there, where the loader never looks (§ *Troubleshooting
  containerized Windows builds*).

## Windows pieces deliberately not reused

Two upstream Windows pieces were evaluated and rejected; both would be regressions here, so do
not "fix" their absence:

- `WindowsAppRunner.Common` (`Invoke-AppRun` / `Resolve-AppExecutablePath`). Its executable probe
  tries `<BuildRoot>\<exe>` first and ends in a recursive first-match search. This tree holds
  **four** copies of the runner exe (`runner\`, `runner\Release\` from the MSIX layout step,
  `runner\<preset>\`, `runner\<preset>\Release\`), so it would launch the flat one and ignore
  `-Configuration` entirely. `Start-Windows.ps1` resolves through
  `Resolve-KataglyphisWindowsLayout` instead, which knows the preset layout and validates the
  Rust plugin DLL beside the exe. `Invoke-AppRun` also has no log parameter, so adopting it would
  drop the `Tee-Object` run log.
- `Invoke-CmakeConfigureAndBuild` (`WindowsCMake.Common`). It makes `-Preset` mandatory (this repo
  also has a generator/`CMAKE_BUILD_TYPE` path), passes no `-S` source directory (the CMake source
  here is `windows/`, not the repo root), and offers no `--target`, while `--target install` is
  what produces the runner bundle. It also fuses configure and build into one step, while the
  `Native Assets Directory Fix` step must run between them.

## Android and cross-toolchain constraints

The rules are in AGENTS.md § 4; the measurements that produced them are here.

- **`--gcc-toolchain` was load-bearing here until 2026-09-29.** A bare `clang` linked against
  the distro GCC; two runs differing only in this flag:

  | `CC` | result |
  | --- | --- |
  | `clang`, no flag | `clang++: error: linker command failed with exit code 1` |
  | `clang --gcc-toolchain=/opt/gcc-16.2.0` | bundle + all four packages |

  So `export_toolchain_env` set the flag through `gcc_toolchain_prefix()`, also after the hub
  deleted its own `export_clang_gcc_toolchain_env` on 2026-09-05 (`aabc7b6e`) as callerless:
  true of the hub, false of this repo. Upstream's "no caller" means no caller *there*.

  **Retired 2026-09-29.** `:latest` ships the `<native-triple>-clang{,++}.cfg` pair beside the
  compiler since then (hub CON16,
  [`linux-cross-builds.md` § *Clang cross wrappers*](../../third_party/ANTfrastructure/docs/linux-cross-builds.md#clang-cross-wrappers)),
  and `export_toolchain_env` checks the selection instead
  (`[Info] CC=clang CXX=clang++, selecting /opt/gcc-16.2.0/lib/gcc/x86_64-pc-linux-gnu/16.2.0`).
  The local native lane then built the bundle and passed the knt ABI and runtime closure gates
  without the rpath the flags used to add.

- **The Android prebuilts are aarch64 now, and the lane's toolchain moved with them.** Until
  2026-09-11 the image carried `ELF x86-64` GStreamer/ONNX Runtime/OpenCV under `/opt/android/`
  while the app builds `arm64-v8a`, so the link died on every archive with
  `incompatible with aarch64linux`. The image now ships only `arm64-v8a` (`libs/arm64-v8a`,
  `jni/abi-arm64-v8a`, and an aarch64 `libgstreamer-1.0.a` built by NDK r29), and the lane links.
  Until 2026-09-17 the workflow's single matrix row (x64) ran under CodeQL, which stopped the
  Gradle build at Kotlin compilation, several steps before the native link (the CodeQL ceiling
  and its observed run, below). Since then CI passes `--run-codeql false` and runs the plain
  `flutter build apk`, native link and the plugin's JVM test included: green on every completed
  run from 2026-09-18 on (36154744222 on 2026-09-25: a 91.8 MB `app-release.apk`).

  The APK is arm64-v8a only: real phones, and the image's x86_64 emulator through its ARM
  translation (the android lane runs it there since 2026-10-06). The native plugin's
  `abiFilters` alone never achieved that: it filters the plugin's own build, while the Flutter
  Gradle plugin writes its three ABIs into the app's `defaultConfig.ndk` and builds `libapp`,
  `libflutter`, `liboxidant` and `libsqlite3` for each. The release APK of run 36891844220
  shipped `armeabi-v7a` and `x86_64` slices with no `libkataglyphis_native_inference.so`. Since
  2026-10-01 the app clears Flutter's list for `kataglyphisAbi`, the build passes
  `--target-platform android-arm64`, and `scripts/linux/check-apk-abi.sh` fails the lane on any
  other slice (AGENTS.md § 4).

  AGP 9.4.1 + Gradle 9.8.1 build that against these constraints, all load-bearing (five in
  AGENTS.md § 4, counting the arm64-v8a pin above as its own):

  - **Built-in Kotlin, with a declared KGP for the version check, and CodeQL has a ceiling under
    it.** `android.builtInKotlin=true` and no `kotlin-android` plugin anywhere: AGP compiles
    Kotlin itself, the target set with `kotlin { compilerOptions { jvmTarget = … } }`. AGP bundles
    KGP 2.2.10, below Flutter's 2.2.20 floor, so `android/settings.gradle.kts` must keep
    `id("org.jetbrains.kotlin.android") version "2.4.21" apply false`: the declaration, not an
    application, raises the classpath KGP. Remove it and Flutter stops with
    `Your project's Kotlin version (2.2.10) is lower than Flutter's minimum supported version of 2.2.20`.

    The floor has a ceiling above it, set by a different tool. CodeQL's Java extractor injects a
    Kotlin compiler plugin whose upper bound sits **below** the KGP this repo declares, so asking
    for a java database killed the whole Gradle build, not just the scan. Observed in run
    34870931651 (2026-09-14), task `:kataglyphis_native_inference:compileReleaseKotlin`:
    `Kotlin version 2.4.20 is too recent. CodeQL currently supports versions below 2.4.20`; then
    `database create` reported `Exit status 1 from command: [/tmp/codeql-build.sh]` and the lane
    exited 2 with no APK. No one KGP satisfies both bounds *and* a java database: Flutter wants
    ≥ 2.2.20, CodeQL wants < 2.4.20, and 2.4.21 is declared.
    `scripts/linux/codeql/codeql-android.sh` therefore builds the cluster for **cpp, c and rust
    only**, where this project's inference code is, and keeps `codeql_analyze_java` callerless in
    `codeql-common.sh` for the day the ceiling clears. Do not "fix" the missing java rows by
    lowering the KGP: that trades a building app for a scan of five glue files.
  - **`android.newDsl=false` stays.** The Flutter Gradle plugin still needs the legacy DSL types,
    AGP 9.4 marks them deprecated, and Gradle 9.7's Kotlin-DSL script compilation turns that into
    `Script compilation errors`. Hence `android/app/build.gradle.kts` opens with
    `@file:Suppress("DEPRECATION", "DEPRECATION_ERROR")`.
  - **Cargokit carries a Gradle 9 port.** `Project.exec` and `Project.buildDir` are gone in
    Gradle 9; `rust_builder/cargokit/gradle/plugin.gradle` injects `ExecOperations` and reads
    `project.layout.buildDirectory`. Upstream Cargokit still has the old calls, so keep this
    patch when bumping the vendored copy. The same file keeps a second patch: from API 37 AGP
    reports the compile SDK as `android-37.0`, which upstream's `substring(8) as int` cannot
    parse; the patch keeps the major version only.
  - **`compileSdk` moved to 37 on 2026-09-29, and the `permission_handler_android` 13.0.1 pin
    went with it.** The 14.x that permission_handler 13.0.2 resolves needs `compileSdk 37`; the
    image shipped android-36 only, from a stale SDK cache (hub CON14), until `:latest` of
    2026-09-29.

## Build pitfalls in detail

Moved here from AGENTS.md on 2026-10-15, which keeps the rule and links this detail.

### Android SDK components pinned to the image

**Every Android SDK component must be pinned to what the image ships.** `/opt/android-sdk` is
read-only, so a component the Android Gradle Plugin asks for and does not find cannot be
installed: Gradle stops with `The SDK directory is not writable`, one component per run. AGP's
defaults (build-tools 35.x, NDK 27/28.x, cmake 3.22.1) are all wrong for this image, which
carries 37.0.0 (and 36.0.0), 29.0.14206865 and 4.1.2.

One place pins them (single-sourced 2026-09-17): the `extra` block in `android/build.gradle.kts`
(`kataglyphisCompileSdk`, `kataglyphisBuildTools`, `kataglyphisNdk`, `kataglyphisCmake`;
`kataglyphisAbi` beside them is the APK's one ABI, § *Android and cross-toolchain constraints*).
Its global `subprojects` override sets compileSdk, build-tools and NDK on every Android module,
which also drags third-party plugins such as permission_handler up from their own
`compileSdk 35`, so `android/app`, the native plugin's `android/` and `rust_builder/android/`
carry no literals of their own; the plugin reads its CMake version from the same block. The
override block must sit **above** the `evaluationDependsOn(":app")` block: that one forces
evaluation, and registering `afterEvaluate` afterwards throws
`Cannot run Project.afterEvaluate(Action) when the project is already evaluated`.

### The Rust manifest path

**The Rust manifest path must be counted from the *resolved* plugin dir.** Cargokit builds
`CARGOKIT_MANIFEST_DIR` by string-joining `${CMAKE_CURRENT_SOURCE_DIR}/${manifest_dir}`, and for
a Flutter plugin that directory is the ephemeral symlink
`linux/flutter/ephemeral/.plugin_symlinks/oxidant`: six levels deep, pointing at
`rust_builder/`, which is two. The kernel resolves the symlink *before* applying the `..`, so a
chain counted from the symlink overshoots to `/` and Dart reports
`PathNotFoundException: … /third_party/OxidANT/Cargo.toml`. `rust_builder/linux/CMakeLists.txt`
therefore takes `REALPATH` of `CMAKE_CURRENT_SOURCE_DIR` first, which yields `../..` and survives
the resolution. Verified against a rebuilt directory tree: six `..` fail, two succeed.

`rust_builder/windows/CMakeLists.txt` must KEEP `CMAKE_CURRENT_SOURCE_DIR`; the asymmetry is
deliberate, proved by a full container build on 2026-09-17. Windows normalizes `..`
**lexically**, so the ups counted from the junction path land on the repo root there, and the
REALPATH form fails with `PathNotFoundException: …\third_party\OxidANT\Cargo.toml`. Do not
"unify" the two.

### ONNX Runtime in the Windows runner

**ONNX Runtime is the image's chain build, staged by the build and checked at launch** (owner
rule 2026-09-23). Never copy an ORT into the runner by hand.

- **Staging.** `Build-Windows.ps1`'s *Stage Chain ONNX Runtime* step copies `onnxruntime.dll`
  (+ `DirectML.dll`, `onnxruntime_providers_shared.dll`) from `$env:ONNX_ROOT\bin` beside the exe
  on every build, whatever `KATAGLYPHIS_RUST_FEATURES` says, after the GStreamer glob (which
  skips ORT-family DLLs). The staging is the hub's `Copy-ChainOrtBeside`
  (`WindowsOrtPayload.Common`, this repo's own code until 2026-09-25).
- **Proof.** ANTfrastructure's G6 census (`Test-OrtProvenanceTree` in
  `WindowsOrtProvenance.Common`) then proves the whole runner against the image's chain ORT, byte
  for byte, and that every importer finds it beside the exe; the pass is stamped in
  `ort-chain-stamp.json`. The stamp is `scripts/windows/modules/WindowsOrtRunner.Common.psm1`,
  whose Pester suite runs in the `ort-runner-suite` job of `windows-x64.yml` and of
  `windows-arm64.yml`.
- **Launch.** `Start-Windows.ps1` re-runs G6 on the host with the stamped copy as the reference,
  and refuses a runner whose ORT is missing, unstamped, changed, stray or foreign: Windows
  resolves `onnxruntime.dll` in the exe dir and then System32, where Windows ML ships its own
  1.17. It also refuses an `ORT_DYLIB_PATH` that is not those same bytes, and OxidANT's loader
  (`ort_runtime.rs`) refuses a non-chain file at run time whoever names it. A runner built before
  G6 has an older stamp: rebuild it.
- **`runner\Release`**, the MSIX copy and `Start-Windows.ps1`'s default, is rebuilt from the
  first preset on every build, host copy too, and re-proven before `msix:create`: § *Windows
  build-step traps and MSIX packaging*.
- **arm64.** The natives get the same proof and stamp in `Build-WindowsArm64Natives.ps1`, over a
  copy of `runtime\` with `AccelerANTgine.exe` standing in for the app's exe (G6 places ORT from a
  host exe's folder, and without one it calls every importer `UNRESOLVED`, run 36891845685); the
  device re-proves the stamp before the launch smoke.

Every verdict is the hub's, so both scripts stop with the hub commit to move to when the pinned
hub predates either module. The Linux bundle's twin is `check-bundle-closure.sh` (AGENTS.md § 4,
the packaged Linux artifact).

### Cargokit's Rust toolchain

**Cargokit builds `liboxidant` with the toolchain rustup resolves for OxidANT, never a floating
`stable`** (2026-10-05). Upstream runs `rustup run stable cargo build` when `cargokit.yaml` names
no toolchain. The Linux image then carried only `1.98.1` and a dated nightly, so every native and
Android build downloaded the day's stable and shipped a `liboxidant.so` stamped
`rustc version 1.99.0`. The `:latest` of 2026-10-10 carries 1.99.0, and the patch stays: whenever
the image's pin lags the newest stable, a floating `stable` downloads again. The fix is a local
patch in `rust_builder/cargokit/build_tool/lib/src/`; keep both halves when bumping the vendored
copy:
- `builder.dart` asks `rustup show active-toolchain` (through `rustup.dart`'s `activeToolchain`)
  in the crate dir, which follows `RUSTUP_TOOLCHAIN`, then a `rust-toolchain.toml`, then the
  default.
- `rustup.dart` counts a version pin such as `1.98.1-<host>` as installed. Upstream lists only
  channel names, so a pin would read as missing.

The Windows image's default is the `stable-…` it installed at build time, so Windows resolves to
the toolchain it already used. `scripts/linux/check-rust-toolchain.sh` reads the
`rustc version` stamp in `.comment` and fails the native lane (bundle) and the Android lane (APK)
on any other version; its suite, `scripts/linux/tests/test-check-rust-toolchain.sh`, runs in both
lanes' code-quality batches. The Android lane still adds `aarch64-linux-android` to the pinned
toolchain at build time (about 4 s), because the image lacks that target.

### The Linux plugin's AccelerANTgine build

**The Linux plugin builds AccelerANTgine without its test suites and without its Debug
sanitizers.** `packages/kataglyphis_native_inference/linux/CMakeLists.txt` sets
`BUILD_TESTING`, `myproject_ENABLE_SANITIZER_ADDRESS` and `myproject_ENABLE_SANITIZER_UNDEFINED`
to OFF before `add_subdirectory`, as it already set `myproject_ENABLE_CACHE`. Without them the
Debug app build that `flutter test integration_test/… -d linux` makes failed twice, both
reproduced in `:latest` (2026-10-01):
- AccelerANTgine's Debug default turns on ASan and UBSan, and its public options target carries
  the flags into the plugin, so the uninstrumented runner cannot link: 58 undefined
  `__asan_*`/`__ubsan_*` references from both libraries (run 36900441698).
- Its tests add FuzzTest in Debug, and on Linux the vendored ANTLR's install rule names a
  `libantlr4-runtime.so.4.13.2` that is never built.

Side effect: Release builds lost AccelerANTgine's googletest headers and archives from the
bundle; the plugin's gtest fetches its own googletest. Windows is unchanged: its Debug preset
ships ASan on purpose.

## The Windows lanes in detail

Moved here from AGENTS.md on 2026-10-15, which keeps the rules and links this detail.

Windows builds run containerized, and **CI runs the exact same script**:
[`windows-x64.yml`](../../.github/workflows/windows-x64.yml) calls `Build-Windows.ps1` through
ANTfrastructure's `run-in-windows-container` action, so "works locally" and "works in CI" are the
same steps by construction. Locally:

```powershell
& "$env:ProgramFiles\Stevedore\bin\docker.exe" run --rm --isolation process `
  --mount "type=bind,source=$PWD,target=C:\ws-mnt" -w C:\ws-mnt `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64 `
  pwsh -NoProfile -ExecutionPolicy Bypass -File C:\ws-mnt\scripts\windows\Build-Windows.ps1 `
    -SkipMsixPackaging
```

**The parity run is `-SkipMsixPackaging` alone**, and **run it in the container, not on the
host**: the Windows engine is Stevedore's, not Rancher Desktop's, and the host's `cmake`
(Strawberry Perl's 3.29.2) is too old for `cmake_minimum_required(VERSION 3.31.6)`. The
2026-09-06 parity run, what it produced, the stale pre-rename artifacts beside it and the engine
detail: § *Windows build-step traps and MSIX packaging*.

**The mount target must not already exist in the image** (it fails at container creation;
images before 2026-09-26 held `C:\workspace`): § *Containerized build (Stevedore, recommended)*.

**On the dev box the command above fails as written; junction first.** On this skewed host,
Dart's and CMake's write-then-rename steps fail on the bind mount under a real build (AGENTS.md
§ 4). The command then reds up to ten steps: `PathNotFoundException` on Flutter's `sqlite3.dll`
copy, and a `GOOGLE_BENCHMARK` `try_run` that cannot find its own `cmTC_*Targets.cmake`. Two
things fix it:
- Start from a checkout with no root or plugin `.dart_tool`/`build`. A Linux lane's plugin
  `package_config.json` reds *Dart Analysis* on its own.
- Inside the container, junction those four directories to container-local ones before
  `Build-Windows.ps1`: § *Containerized build (Stevedore, recommended)*.

With both, all three of `windows-x64.yml`'s container steps passed locally on 2026-10-05 (27/27,
24/24, 20/20 steps). CI's fresh clone on `windows-2025` needs neither.
`Build-Windows-Container.ps1` avoids both by construction: it streams the sources into the
container instead of mounting them, and leaves the root `build` and every `.dart_tool` out
(§ *Tar-pipe inbound exclusions*).

Six quality/output steps run before the native build (`-CodeQL` short-circuits before them), each
skippable with its switch: **Dart format + CMake format** (`-SkipFormat`), **Dart analyze +
Flutter tests + Plugin Flutter tests** (`-SkipTests`), **API docs generation** (`-SkipDocs`).
`-SkipTests` also skips **Build Native Plugin Tests (gtest)**, which builds the plugin's gtest
after each preset's runner is staged; `windows-x64.yml` runs it on the host, since
`flutter_windows.dll` does not load in the Server Core image (0xC0000135). The format gate's
tracked file list and the dartdoc workaround: § *Windows build-step traps and MSIX packaging*.

**A failed step does not abort the run.** No step is declared `-Critical` and `-StopOnError` is
off by default, so the step is recorded and the build carries on: the log still ends with
`=== Build Complete ===` when something failed, and the script exits 1 only from its `finally`
block. A real run shows both lines together (`FAILED: MSIX Packaging` … `=== Build Complete ===`).
**Trust the process exit code and `failedSteps` in `logs/build-summary-*.json`, never the log
tail.**

- Preset aliases: `clangcl-{debug,profile,release}`, `msvc-{debug,release}`,
  `clang-{debug,profile,release}` → `x64-ClangCL-Windows-Debug` etc.
- Switches: `-SkipTests`, `-SkipFormat`, `-SkipDocs`, `-CleanBuild`, `-SkipMsixPackaging`,
  `-SkipBootstrapFlutterBuild`, `-ContinueOnError`/`-StopOnError`, `-CodeQL`. The closing
  **Delivery Check** cannot be skipped.
- Logs land in `logs/` (`build-windows-*.log` + `build-summary-*.json`); API docs in `doc/api`
  (git-ignored).

**The agentic loop (adopted 2026-09-13).** `scripts/agentic-loop/` holds the config, both runner
wrappers and the project prompt overlays. Engine `opencode`, executor
`opencode-go/deepseek-v4.1-flash`, planner `opencode-go/glm-5.2`. It runs on the host and builds
through `scripts/windows/Build-Windows-Container.ps1`, which drives `Build-Windows.ps1` in a
**reused** Stevedore container (tar-pipe transport, `WindowsContainerBuild.Reuse`, so
Cargo/sccache/pub caches survive) and always skips docs and MSIX. Tests are `-TestsOnly`: the Dart
gates in the same container. The config contract and build-matrix semantics are owned by
[`third_party/ANTfrastructure/docs/windows-agentic-loop.md`](../../third_party/ANTfrastructure/docs/windows-agentic-loop.md);
`.opencode/agents/` is generated and gitignored: edit the overlays, never it.

**The engine is opencode v2, on Windows and Linux alike (owner directive 2026-09-28).** Never
install or run opencode v1 for this loop; the pinned hub refuses a v1 on `PATH` with a FATAL.
Installing v2, logging in again under it, and why the loop passes `--standalone` and `--auto`:
[`windows-agentic-loop.md` § *opencode v2*](../../third_party/ANTfrastructure/docs/windows-agentic-loop.md#opencode-v2).
Then check `opencode models` for both model IDs above.

```powershell
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1            # planner + executor
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1 -DryRun    # wiring check
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1 -PlannerOnly
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1 -ExecutorOnly
```

The loop does not watch CI and auto-commits with `git add -A`: check whether it is live before
working interactively in the same tree. The loop itself is ANTfrastructure's:
[`docs/adopting-in-a-new-project.md` § 4](../../third_party/ANTfrastructure/docs/adopting-in-a-new-project.md#4-the-agentic-loop).

**MSIX packaging** runs only locally, since CI passes `-SkipMsixPackaging`; that is how both
halves stayed broken unnoticed until 2026-09-03. Why `msix_config.build_windows` is `false` and
what the **MSIX Compatibility Layout** step does: § *Windows build-step traps and MSIX
packaging*.

**The CI lane** ([`windows-x64.yml`](../../.github/workflows/windows-x64.yml)): its steps, the
`build-clang-debug` and `ort-runner-suite` jobs, the four host steps and the three checkout
consequences with the gitdir-length table, the two directory renames that fixed it and why a
local checkout is the worst case: § *The Windows CI lane and the `$GIT_DIR` limit*.

**The Windows arm64 lane is a hybrid** ([`windows-arm64.yml`](../../.github/workflows/windows-arm64.yml),
2026-09-27). Flutter cannot cross-build `windows-arm64` from an x64 host (flutter/flutter#62597),
so the lane has three build jobs (and the `ort-runner-suite` Pester job, below):
- `natives` runs `scripts/windows/Build-WindowsArm64Natives.ps1` in the hub's arm64 container
  lane. It cross-builds AccelerANTgine and `oxidant.dll` without DirectML, because the arm64 ORT
  has no DirectML EP.
- `app` builds the Flutter part natively on `windows-11-arm` against those, with clang-cl like
  every other Windows build here: `scripts/windows/Build-WindowsArm64App.ps1`. Two environment
  switches do it: `CARGOKIT_PREBUILT_DIR`, a local Cargokit patch, copies the DLL and skips
  cargo; `KATAGLYPHIS_ACCELERANTGINE_PREBUILT` makes the plugin link an imported AccelerANTgine
  instead of `add_subdirectory`. With both unset, x64 builds exactly as before.
- `app-debug` builds the same app as a Debug (ASan) one:
  `Build-WindowsArm64App.ps1 -Configuration Debug`, /MD like the natives (clang-cl strips /MDd
  under ASan, so no debug CRT), the aarch64 ASan runtime staged from the runner's own VS; the
  launch smoke proves the instrumented app starts.

The lane went green in run 36322839058 and has built with clang-cl since test run 36622834879
(2026-09-29). On the device the app tree passes the hub's import walk (40 files, 0 unresolved),
and the app stays up 20 s at 147 MB with a real window. Two traps surfaced on the way:
- **Never a plain `flutter build windows` there.** Flutter hands CMake the Visual Studio
  generator without a toolset, so MSVC's `cl` compiled the whole app. First it stopped at
  clang-cl's `-Wno-…` flags (D8021). Then, once the runner moved to VS 2026
  (`windows-11-vs2026-arm64`, MSVC 14.51, 2026-09-29), it stopped at permission_handler_windows'
  `/await` (STL1011). The script builds the way x64 does:
  - Flutter's `--config-only` runs under the ClangCL toolset, through a toolchain file in
    `CMAKE_TOOLCHAIN_FILE`.
  - Then Ninja and VS's own clang-cl build the app.
  - It fails when either build tree recorded any other compiler.

  `APPLY_STANDARD_SETTINGS` still gives the `-Wno-…` flags to clang only; that guard is for the
  MSVC presets.
- `.plugin_symlinks` is a junction there that `REALPATH` leaves unresolved. That is why the
  cross-built AccelerANTgine brings its own C API headers.

The app job tests what it built with the x64 lane's scripts: `Invoke-FlutterTests.ps1` (the
app's and the plugin's Dart suites on the arm64 Dart VM, one `TESTS:` line), `Test-KntAbi.ps1`,
`Invoke-PluginGTest.ps1` (the target `Build-WindowsArm64App.ps1` builds), and
`Test-LaunchSmoke.ps1 -OrtStamp`. Its `ort-runner-suite` job runs the Pester suite on
`windows-11-arm`.
