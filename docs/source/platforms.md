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
> container before building. The plugin's pair needs it too: its tests copy into
> `packages\kataglyphis_native_inference\build\unit_test_assets` (measured 2026-10-05):
>
> ```powershell
> docker exec <name> cmd /c "mkdir C:\dtool & mkdir C:\fbuild\native_assets\windows & mkdir C:\pdtool & mkdir C:\pbuild & mklink /J C:\ws-mnt\.dart_tool C:\dtool & mklink /J C:\ws-mnt\build C:\fbuild & mklink /J C:\ws-mnt\packages\kataglyphis_native_inference\.dart_tool C:\pdtool & mklink /J C:\ws-mnt\packages\kataglyphis_native_inference\build C:\pbuild"
> ```
>
> `mklink /J` refuses a directory that already exists, so move the host's four aside first.
> Remove the junctions with a plain `rmdir` before the container exits; otherwise the host keeps
> four junctions to paths that only existed in the container.
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
| CMake configure: `add_subdirectory ... .plugin_symlinks/kataglyphis_native_inference/windows which is not an existing directory` (only this one plugin) | `Fix-FlutterPluginSymlinks` (now `Repair-FlutterPluginSymlink`, the old name kept as an alias) used to **copy** each plugin dir into `.plugin_symlinks`; it now makes a junction first and copies only when that does not resolve. For `kataglyphis_native_inference` the recursive copy of its deep `native/AccelerANTgine/third_party/*` tree overruns the 260-char path limit and aborts before `windows\` is copied, leaving a broken junction. Since 2026-09-05 that tree is no longer inside the plugin — the inference core is a sibling submodule at `third_party/AccelerANTgine` and the plugin directory is about 100 files — so a copy would no longer overrun; the junction stays regardless, as the cheaper and more robust option | Use a **junction** (`mklink /J`) rather than a copy for container-local workspaces — immune to MAX_PATH (the "copy avoids symlink access-denied" rationale only applies to bind-mounted paths). Clear stale `windows\flutter\ephemeral` + `.dart_tool` first: a broken junction from a prior run makes `flutter build --config-only` crash `PathExistsException` (errno 183, "already exists"). |
| App window flashes then exits on the host (~6 MB, no window title) | The native C++ plugin can't load its dependency `AccelerANTgine.dll`. Before 2026-10-17 the x64 build left it, the VC++ runtime and a second ORT in a `bin\` **subdirectory** of the runner, where the loader never looks, so the released zip only started with `bin\` on `PATH` | Fixed at the source: the plugin's `CMakeLists.txt` sets `CMAKE_INSTALL_BINDIR` and `CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION` to `.` before it embeds AccelerANTgine, so both land beside the exe, as on arm64. The x64 launch smoke starts the runner without any `-SearchPath`, as a double-click does. A runner that still has a `bin\` is from an older build: rebuild. A fully-initialized app is ~130 MB with a real window handle. |

### Tar-pipe inbound exclusions

`Build-Windows-Container.ps1` streams the checkout into the reused container with bsdtar, and bsdtar
aborts the **whole** archive on any entry it cannot stat: the host's Flutter plugin junctions under
`ephemeral/` and the Linux symlinks the cargo-cache sync-back leaves in `third_party/OxidANT/target` are
both such entries, so both stay excluded (the container regenerates the first and builds into its own
`CARGO_TARGET_DIR` instead of the second). The patterns match whole path components **at every depth**,
so a root directory cannot be excluded by name: `build` would also take
`third_party/ANTfrastructure/windows/scripts/build` with it, and no pattern form anchors (`./build`,
`[.]/build` and `build/` all behave the same). The root directories are omitted from the item list
instead (`-InboundItems`, computed in the driver); the patterns cover the deep directories, and none is
a prefix glob like `out*`, which would drop unrelated directories such as nlohmann's `detail/output/`.
Of `.git` only `modules/` and the object store are left out: the CMake format gate's `git ls-files`
needs HEAD, the index and refs, never an object.

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

`Build-Windows.ps1 -?` lists the rest. CI's Release job (`build-clang`) passes only
`-SkipMsixPackaging`, so that invocation is the parity run — see AGENTS.md § 5; its Debug
job adds `-Configurations clangcl-debug -SkipFormat -SkipDocs`.

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
generated and gitignored — a build without it waits 20 s for the core at
start-up, then runs without it (only the About page's Rust demo needs it):

```bash
# The image's dated nightly, as the lane takes it; the floating one breaks in :latest (AGENTS.md § 4).
nightly="$(sed -n 's/^RUST_NIGHTLY_TOOLCHAIN=//p' third_party/ANTfrastructure/linux/scripts/01-core/versions.env)"
rustup toolchain install "$nightly" --component rust-src --target wasm32-unknown-unknown
flutter_rust_bridge_codegen build-web --release --rust-root third_party/OxidANT \
  --wasm-pack-rustup-toolchain "$nightly"
```

Run Flutter web with COOP/COEP headers; Firefox and Safari load the core's
shared-memory wasm only on a cross-origin isolated page:

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
  Those `TryCompile`s are also the 63 C/C++ misses the native lane's sccache stats
  show on every run: the launchers are environment variables, so the configure checks
  compile through sccache too, each in a `CMakeScratch/TryCompile-*` directory with a
  random name that no later run repeats. AccelerANTgine configured twice in `:latest`
  missed 21 of 32 such compiles the second time (2026-10-16), and the lane configures
  three times (release, the integration test's debug, the performance test's profile).
  Every real source hits, and the checks are tiny; raising `SCCACHE_CACHE_SIZE` changed
  nothing (4cccd4e, reverted in 7242bb8).

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
  (`Get-ProjectDartFiles`, 85 files on 2026-10-14), **not `.`**: `dart format .` recurses into
  `.git`, and the deeply nested vendored submodule gitdir exceeds Windows
  MAX_PATH, so the listing throws and the gate crashes before formatting
  anything.
- Docs generation does **not** use the SDK-bundled `dart doc`. The dartdoc 9.0.4
  the image carried at the time crashes on *any* Flutter app — a `_stripDocImports`
  RangeError while precaching the Flutter SDK's own `@docImport` comments
  (reproduced with a bare `flutter create`). The step `pub global activate
  dartdoc` (≥ 9.0.9, which fixes it) and runs that — 9.0.9 in the 2026-09-25 CI
  run. The image has since moved on (the hub pins Flutter 3.47.7 today), and the Linux
  lane's `generate-docs.sh` runs its bundled `dart doc` without trouble.

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

### `-ftime-trace` stays on, though nothing reads the traces

`Build-Windows.ps1` passes `-DKATAGLYPHIS_ENABLE_TIME_TRACE=ON` and CMake's configure profile
to every configure, and no step or workflow reads either. It looks like dead weight that also
costs speed: sccache cannot cache a compile with `-ftime-trace`, which run 38711050047's Debug
build reports as `Non-cacheable reasons: -ftime-trace 279`, all its C++ units. That is what
keeps a reused container safe, though. The image's sccache 0.18 with clang-cl hashes a C++23
module importer without the BMIs it imports, so after an interface edit a warm cache hands back
the old object (hub `docs/windows-container-build-performance.md` § *sccache on a C++23
modules build*). Take the flag out only once the image's sccache carries mozilla/sccache#2876,
or with sccache off for the C++ units.

## The Windows CI lane and the `$GIT_DIR` limit

**The CI lane** ([`windows-x64.yml`](../../.github/workflows/windows-x64.yml))
is three ANTfrastructure actions, one hub script and GitHub's
`actions/upload-artifact`:
`prepare-windows-container-host` (long paths, short-path clone, data-root move,
disk check, GHCR login, pull), the hub's `windows/scripts/Invoke-Lint.ps1 -Path
scripts` (parse gate plus AST traps over this repo's own PowerShell, on the host
before the image pull), `run-in-windows-container`, `actions/upload-artifact`
and `upload-codeql-sarif`. The workflow has two more jobs. `build-clang-debug` runs
`Build-WindowsDebugApps.ps1` in one container: the `clangcl-debug` preset (ASan + UBSan),
copied to `…-Debug-app`, then the same preset with `-FlutterTarget
integration_test/simple_test.dart` on the first build's tree, and Microsoft's ASan runtime
(`Stage-AsanRuntime.ps1`) beside both. The launch smoke runs the copy, and
`Invoke-WindowsIntegrationTest.ps1` drives the integration app.
`ort-runner-suite` is a plain checkout plus `run-pester-suite` over `scripts/windows/tests`,
with no container; `windows-arm64.yml` runs the same job on `windows-11-arm`. After the
upload, four host steps test the runner outside the image: this repo's
`Test-KntAbi.ps1` and `Invoke-PluginGTest.ps1` (the plugin's gtest, built in the
image, where `flutter_windows.dll` does not load), the hub's `Test-TargetArch.ps1
-ImportWalk -Standalone`, and `Test-LaunchSmoke.ps1 -OrtStamp`, which re-proves
the G6 stamp before it starts the app. Three consequences:

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

## The app's Windows installers

Since 2026-10-17 every release carries the app as an MSI and a signed MSIX for x64 and arm64,
beside the zip. `scripts/windows/Package-OmniAccelerANT.ps1` makes both from the runner folder.
`scripts/windows/modules/WindowsAppInstallers.Common.psm1` (`New-AppMsi`, `New-AppMsix`) holds
the part ObservANT's packaging shares.

- **Built where the app is**: in the x64 lane's `build-clang` job on the `windows-2025` host, and
  in the arm64 lane's `app` job on `windows-11-arm`. Each installs WiX 7.0.0 as a dotnet tool,
  the version the image pins, and uses the runner's Windows SDK for `makeappx` and `signtool`.
  Neither runner image ships a .NET SDK, so `actions/setup-dotnet` puts 10.0 there first; WiX 7
  is a net8.0 tool that rolls forward to it.
- **First proof, 2.1.0 on develop** (runs 39038477716 and 39038479571): x64 MSI 46 MB and MSIX
  54 MB, arm64 MSI 34 MB and MSIX 41 MB, all twelve installer checks passing on both.
- **The MSI** (`scripts/windows/installer/omni-accelerant.wxs`) installs per machine into
  `Program Files\OmniAccelerANT` with a Start menu shortcut, and upgrades in place (one
  `UpgradeCode`). Its version is `pubspec.yaml`'s `version:`.
- **The MSIX** (`scripts/windows/installer/AppxManifest.xml`) has the identity
  `Kataglyphis.OmniAccelerANT` and the `msix_version` of `msix_config`. A throwaway test
  certificate signs it, and its `-testcert.cer` ships beside it. A tester trusts that `.cer`
  under `LocalMachine\TrustedPeople` before installing.
- **`Test-OmniAccelerANTInstallers.ps1`** installs the MSI with `msiexec /qn` and checks:
  `AccelerANTgine.dll` sits beside the exe with no `bin\`, the exe, the plugin and
  AccelerANTgine.dll match the lane's architecture, and the Start menu shortcut exists. It then
  starts the installed app through `Test-LaunchSmoke.ps1` without any `-SearchPath`, so it starts
  as the shortcut does. For the MSIX it checks the signature, identity and architecture, trusts
  the certificate, runs `Add-AppxPackage`, starts the package through its app entry, and removes
  it again.
- **A runner with a `bin\` folder is refused** by the packaging script: before 8f5ed5e the x64
  build left AccelerANTgine.dll there, where the loader never looks (§ *Troubleshooting
  containerized Windows builds*).

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

- **`--gcc-toolchain` was load-bearing here until 2026-09-29, and ANTfrastructure
  deleted the helper that set it.** `export_clang_gcc_toolchain_env` went away upstream on
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
  source-built GCC 16.2.0 the image provides. `export_toolchain_env` then restored
  the flags through `gcc_toolchain_prefix()`, which upstream kept. (All of this is
  history: see *Retired 2026-09-29* below.)

  The wider lesson for every ANTfrastructure bump: upstream reasons about its own
  tree when it removes something. "No caller" means no caller *there*.

  **Retired 2026-09-29.** `:latest` since then ships `<native-triple>-clang{,++}.cfg`
  beside the compiler (hub CON16), so a bare `clang++` selects
  `/opt/gcc-16.2.0` by itself. `export_toolchain_env` stopped injecting
  `--gcc-toolchain`, `-L` and `-rpath` and now checks the selection instead
  (`[Info] CC=clang CXX=clang++, selecting /opt/gcc-16.2.0/lib/gcc/x86_64-pc-linux-gnu/16.2.0`).
  The local native lane then built the bundle and passed the knt ABI and runtime
  closure gates without the rpath the flags used to add.

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
  The APK is arm64-v8a only: real phones, and the image's x86_64 emulator through
  its ARM translation (the android lane runs it there since 2026-10-06). The native
  plugin's `abiFilters` alone never achieved that: it filters the plugin's own
  build, while the Flutter Gradle plugin writes its three ABIs into the app's
  `defaultConfig.ndk` and builds `libapp`, `libflutter`, `liboxidant` and
  `libsqlite3` for each. The release APK of run 36891844220 shipped
  `armeabi-v7a` and `x86_64` slices with no `libkataglyphis_native_inference.so`.
  Since 2026-10-01 the app clears Flutter's list for `kataglyphisAbi`, the build
  passes `--target-platform android-arm64`, and `scripts/linux/check-apk-abi.sh`
  fails the lane on any other slice (AGENTS.md § 4).
  AGP 9.4.1 + Gradle 9.8.1 builds that against these constraints, all
  load-bearing (five, counting the arm64-v8a pin above as its own, in AGENTS.md § 4):

  - **Built-in Kotlin, with a declared KGP for the version check — and CodeQL
    has a ceiling under it.** `android.builtInKotlin=true` and no
    `kotlin-android` plugin anywhere; AGP compiles Kotlin itself, and the target
    is set with `kotlin { compilerOptions { jvmTarget = … } }`. AGP bundles KGP
    2.2.10, below Flutter's 2.2.20 floor, so `android/settings.gradle.kts` must
    keep `id("org.jetbrains.kotlin.android") version "2.4.21" apply false` — the
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
    Flutter wants ≥ 2.2.20, CodeQL wants < 2.4.20, and 2.4.21 is what is
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
    still has the old calls, so keep this patch when bumping the vendored copy. The
    same file keeps a second patch: from API 37 AGP reports the compile SDK as
    `android-37.0`, which upstream's `substring(8) as int` cannot parse; the patch keeps
    the major version only.
  - **`compileSdk` moved to 37 on 2026-09-29, and the `permission_handler_android`
    13.0.1 pin went with it.** The 14.x that permission_handler 13.0.2 resolves
    needs `compileSdk 37`; the image shipped android-36 only, from a stale SDK
    cache (hub CON14), until `:latest` of 2026-09-29.

## Build pitfalls in detail

Moved here from AGENTS.md on 2026-10-15, which keeps the rule and links this detail.

### Android SDK components pinned to the image

**Every Android SDK component must be pinned to what the image ships.**
`/opt/android-sdk` is read-only, so any component the Android Gradle Plugin
asks for and does not find cannot be installed — Gradle stops with
`The SDK directory is not writable`, one component per run. AGP's defaults
(build-tools 35.x, NDK 27/28.x, cmake 3.22.1) are all
wrong for this image, which carries 37.0.0 (and 36.0.0), 29.0.14206865 and 4.1.2. One
place pins them (single-sourced 2026-09-17): the `extra` block in
`android/build.gradle.kts` (`kataglyphisCompileSdk`, `kataglyphisBuildTools`,
`kataglyphisNdk`, `kataglyphisCmake`; `kataglyphisAbi` beside them is the APK's
one ABI, below). Its global `subprojects` override sets
compileSdk, build-tools and NDK on every Android module — which also drags
third-party plugins such as permission_handler up from their own
`compileSdk 35` — so `android/app`, the native plugin's `android/` and
`rust_builder/android/` carry no literals of their own; the plugin reads its
CMake version from the same block. The override block has to sit **above**
the `evaluationDependsOn(":app")` block — that one forces evaluation, and
registering `afterEvaluate` afterwards throws `Cannot run
Project.afterEvaluate(Action) when the project is already evaluated`.

### The Rust manifest path

**The Rust manifest path must be counted from the *resolved* plugin dir.**
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
succeed. `rust_builder/windows/CMakeLists.txt` must KEEP
`CMAKE_CURRENT_SOURCE_DIR` — the asymmetry is deliberate and was proved by a
full container build on 2026-09-17: Windows normalizes `..` **lexically**, so
the ups counted from the junction path land on the repo root there, and the
REALPATH form fails with `PathNotFoundException: …\third_party\OxidANT\
Cargo.toml`. Do not "unify" the two.

### ONNX Runtime in the Windows runner

**ONNX Runtime is the image's chain build, staged by the build and checked at
launch** (owner rule 2026-09-23). `Build-Windows.ps1`'s *Stage Chain ONNX
Runtime* step copies `onnxruntime.dll` (+ `DirectML.dll`,
`onnxruntime_providers_shared.dll`) from `$env:ONNX_ROOT\bin` beside the exe on
every build, whatever `KATAGLYPHIS_RUST_FEATURES` says, after the GStreamer
glob (which skips ORT-family DLLs). ANTfrastructure's G6 census
(`Test-OrtProvenanceTree` in `WindowsOrtProvenance.Common`) then proves the
whole runner against the image's chain ORT, byte for byte, and that every
importer finds it beside the exe; the pass is stamped in `ort-chain-stamp.json`.
`Start-Windows.ps1` re-runs G6 on the host with the stamped copy as the
reference, and refuses a runner whose ORT is missing, unstamped, changed, stray
or foreign — Windows resolves `onnxruntime.dll` in the exe dir and then
System32, where Windows ML ships its own 1.17. It also refuses an
`ORT_DYLIB_PATH` that is not those same bytes, and OxidANT's loader
(`ort_runtime.rs`) refuses a non-chain file at run time whoever names it. A
runner built before G6 has an older stamp: rebuild it. `runner\Release`, the
MSIX copy and `Start-Windows.ps1`'s default, is rebuilt from the first preset
on every build (the host copy too), and *MSIX Packaging* re-runs G6 on it before
`msix:create`. Never copy an ORT into
the runner by hand. The staging is the hub's `Copy-ChainOrtBeside`
(`WindowsOrtPayload.Common`, this repo's own code until 2026-09-25); the stamp
is `scripts/windows/modules/WindowsOrtRunner.Common.psm1`, whose Pester suite
runs in the `ort-runner-suite` job of `windows-x64.yml` and of `windows-arm64.yml`.
The arm64 natives get the same proof and stamp in `Build-WindowsArm64Natives.ps1`,
over a copy of `runtime\` with `AccelerANTgine.exe` standing in for the app's exe
(G6 places ORT from a host exe's folder, and without one it calls every importer
`UNRESOLVED`, run 36891845685); the device re-proves the stamp before the launch smoke. Every verdict is the hub's,
so both scripts stop with the hub commit to move to when the pinned hub
predates either module. The Linux bundle's twin is
`check-bundle-closure.sh` (the packaged-Linux-artifact bullet above).

### Cargokit's Rust toolchain

**Cargokit builds `liboxidant` with the toolchain rustup resolves for OxidANT,
never a floating `stable`** (2026-10-05). Upstream runs `rustup run stable cargo
build` when `cargokit.yaml` names no toolchain. The Linux image then carried only
`1.98.1` and a dated nightly, so every native and Android build downloaded the
day's stable and shipped a `liboxidant.so` stamped `rustc version 1.99.0`. The
`:latest` of 2026-10-10 carries 1.99.0, and the patch stays: whenever the image's
pin lags the newest stable, a floating `stable` downloads again. A
local patch in `rust_builder/cargokit/build_tool/lib/src/` fixes it; keep both
halves when bumping the vendored copy:
- `builder.dart` asks `rustup show active-toolchain` (through `rustup.dart`'s
  `activeToolchain`) in the crate dir, which
  follows `RUSTUP_TOOLCHAIN`, then a `rust-toolchain.toml`, then the default.
- `rustup.dart` counts a version pin such as `1.98.1-<host>` as installed.
  Upstream lists only channel names, so a pin would read as missing.

The Windows image's default is the `stable-…` it installed at build time, so
Windows resolves to the toolchain it already used. `scripts/linux/check-rust-toolchain.sh`
reads the `rustc version` stamp in `.comment` and fails the native lane (bundle)
and the Android lane (APK) on any other version. Its suite,
`scripts/linux/tests/test-check-rust-toolchain.sh`, runs in both lanes'
code-quality batches. The Android lane still adds `aarch64-linux-android` to the
pinned toolchain at build time (about 4 s), because the image does not carry that
target.

### The Linux plugin's AccelerANTgine build

**The Linux plugin builds AccelerANTgine without its test suites and without
its Debug sanitizers.** `packages/kataglyphis_native_inference/linux/CMakeLists.txt`
sets `BUILD_TESTING`, `myproject_ENABLE_SANITIZER_ADDRESS` and
`myproject_ENABLE_SANITIZER_UNDEFINED` to OFF before `add_subdirectory`, the
way it already set `myproject_ENABLE_CACHE`. The Debug app build that
`flutter test integration_test/… -d linux` makes failed twice without them,
both reproduced in `:latest` (2026-10-01):
- AccelerANTgine's Debug default turns on ASan and UBSan, and its public
  options target carries the flags into the plugin. The uninstrumented
  runner then cannot link: 58 undefined `__asan_*`/`__ubsan_*` references
  from both libraries (run 36900441698).
- Its tests add FuzzTest in Debug, and on Linux the vendored ANTLR's install
  rule names a `libantlr4-runtime.so.4.13.2` that is never built.

Release builds lost AccelerANTgine's googletest headers and archives from the
bundle as a side effect. The plugin's gtest fetches its own googletest.
Windows is unchanged, since its Debug preset ships ASan on purpose.

## The Windows lanes in detail

Moved here from AGENTS.md on 2026-10-15, which keeps the rules and links this detail.

Windows builds run containerized, and **CI runs the exact same script** — the
workflow [`windows-x64.yml`](../../.github/workflows/windows-x64.yml)
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
[`docs/source/platforms.md`](platforms.md) § *Windows build-step
traps and MSIX packaging*.

**The mount target must not already exist in the image.** `target=C:\workspace`
fails at container creation with `hcs::CreateComputeSystem ... The request is not
supported` on hosts whose Docker/hcsshim is version-skewed from the image —
`C:\workspace` is a baked image dir. Use a fresh target (`C:\ws-mnt` above; CI
mounts `D:\ws → C:\ws`). ANTfrastructure owns the why (AGENTS.md § 2).

**On the dev box the command above fails as written; junction first.** On this
skewed host, Dart's and CMake's write-then-rename steps fail on the bind mount
under a real build (AGENTS.md § 4). The command then reds up to ten steps: `PathNotFoundException`
on Flutter's `sqlite3.dll` copy, and a `GOOGLE_BENCHMARK` `try_run` that cannot
find its own `cmTC_*Targets.cmake`. Two things fix it:
- Start from a checkout with no root or plugin `.dart_tool`/`build`. A Linux
  lane's plugin `package_config.json` reds *Dart Analysis* on its own.
- Inside the container, junction those four directories to container-local
  ones before `Build-Windows.ps1`: [`docs/source/platforms.md`](platforms.md)
  § *Containerized build (Stevedore, recommended)*.

With both, all three of `windows-x64.yml`'s container steps passed locally on
2026-10-05 (27/27, 24/24, 20/20 steps). CI's fresh clone on `windows-2025` needs
neither. `Build-Windows-Container.ps1` avoids both by construction: it streams
the sources into the container instead of mounting them, and leaves the root
`build` and every `.dart_tool` out.

Six quality/output steps run before the native build (`-CodeQL` short-circuits
before them), each skippable with the paired switch: **Dart format + CMake
format** (`-SkipFormat`), **Dart analyze + Flutter tests + Plugin Flutter tests**
(`-SkipTests`), **API docs generation** (`-SkipDocs`). `-SkipTests` also skips
**Build Native Plugin Tests (gtest)**, which builds the plugin's gtest after each
preset's runner is staged; `windows-x64.yml` runs it on the host, since
`flutter_windows.dll` does not load in the Server Core image (0xC0000135).

**A failed step does not abort the run.** None of them is declared `-Critical`,
and `-StopOnError` is off by default, so the step is recorded and the build
carries on — the log still ends with `=== Build Complete ===` even when
something failed, and the script only exits 1 from its `finally` block. A real
run shows both lines together (`FAILED: MSIX Packaging` … `=== Build Complete ===`).
**Trust the process exit code and `failedSteps` in `logs/build-summary-*.json`,
never the log tail.**

Two Windows-specific traps these steps carry: the format gate hands `dart
format` the tracked file list (`Get-ProjectDartFiles`, the list of AGENTS.md § 4)
rather than `.` (the recursive walk reaches the vendored submodule gitdir and
exceeds MAX_PATH), and docs generation
runs a `pub global activate dartdoc` (≥ 9.0.9) instead of the SDK-bundled
`dart doc`, whose 9.0.4 crashes on any Flutter app. Both:
[`docs/source/platforms.md`](platforms.md) § *Windows build-step
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
[`third_party/ANTfrastructure/docs/windows-agentic-loop.md`](../../third_party/ANTfrastructure/docs/windows-agentic-loop.md);
`.opencode/agents/` is generated and gitignored — edit the overlays, never it.

**The engine is opencode v2, on Windows and Linux alike (owner directive
2026-09-28).** Never install or run opencode v1 for this loop. v2 is the npm
package `@opencode/cli`. Install it with `curl -fsSL https://opencode.ai/v2/install | bash`
into `~/.opencode/bin`; on Windows run that from Git Bash with
`--no-modify-path`, then put `%USERPROFILE%\.opencode\bin` first on the user
`PATH`. Scoop and GitHub releases still ship 1.x. v2 does not read v1's saved
login, so run `opencode auth login` once more under v2, then check `opencode
models` for both model IDs above. The loop passes `--standalone` (both roles)
and `--auto` (executor), and the pinned hub refuses a v1 on `PATH` with a
FATAL. Why each flag, and what v1 did instead:
[`windows-agentic-loop.md` § *opencode v2*](../../third_party/ANTfrastructure/docs/windows-agentic-loop.md#opencode-v2).

```powershell
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1            # planner + executor
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1 -DryRun    # wiring check
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1 -PlannerOnly
pwsh -File scripts/agentic-loop/Invoke-AgenticLoop.ps1 -ExecutorOnly
```

The loop does not watch CI and auto-commits with `git add -A`; do not run
interactive work in the same tree without checking whether it is live. The loop
itself is ANTfrastructure's —
[`docs/adopting-in-a-new-project.md` § 4](../../third_party/ANTfrastructure/docs/adopting-in-a-new-project.md#4-the-agentic-loop).

**MSIX packaging.** `msix_config.build_windows` is `false` on purpose — this
script owns the build — and the **MSIX Compatibility Layout** step copies the
preset's output into the flat `runner\Release\` directory that msix looks for.
CI passes `-SkipMsixPackaging`, so packaging is exercised only locally, which is
how both halves stayed broken unnoticed until 2026-09-03:
[`docs/source/platforms.md`](platforms.md) § *Windows build-step
traps and MSIX packaging*.

**The CI lane** ([`windows-x64.yml`](../../.github/workflows/windows-x64.yml))
is three ANTfrastructure actions, one hub script and GitHub's
`actions/upload-artifact`: `prepare-windows-container-host`,
the hub's `windows/scripts/Invoke-Lint.ps1 -Path scripts` (a PowerShell parse
gate on the host, before the ~54 GB image pull), `run-in-windows-container`,
`actions/upload-artifact` and `upload-codeql-sarif` (plus the `ort-runner-suite`
job: a checkout and `run-pester-suite` over `scripts/windows/tests`, no
container). After the upload, four host steps test the runner outside the image,
as the arm64 lane does: `Test-KntAbi.ps1`, `Invoke-PluginGTest.ps1`, the hub's
`Test-TargetArch.ps1 -ImportWalk -Standalone`, and `Test-LaunchSmoke.ps1
-OrtStamp`. Three consequences, each easy to undo by accident:

- It prunes `third_party/DocumANTation` from the recursive checkout. Without
  that, the nested `.git/modules/<name>/` chain makes git abort with
  `fatal: '$GIT_DIR' too big` — git's own limit, not MAX_PATH, so no clone root
  is short enough.
- `mount-source`/`mount-target` stay unset, because the action already defaults
  to `D:\ws` → `C:\ws`, which is where the short-path clone put the tree.
- Artifact paths — and the lint step's `working-directory` — are therefore
  **absolute under the short-path clone** (`steps.prep.outputs.workspace`),
  never relative to `github.workspace`.

The measurements behind all three — the gitdir-length table, the two directory
renames that fixed it, and why a local checkout is the worst case — are in
[`docs/source/platforms.md`](platforms.md) § *The Windows CI lane
and the `$GIT_DIR` limit*.

CI passes `-SkipMsixPackaging`, and `-CodeQL` is off there because of runtimes.

A second job, `build-clang-debug`, builds the `clangcl-debug` preset (ASan + UBSan) and its
integration-test twin in one container (`Build-WindowsDebugApps.ps1`, since 2026-10-15): the
twin reuses the first build's tree, where a container of its own rebuilt all 520 targets
(11:45 of 14.9 min). The plain app is kept as `…-Debug-app` for the launch smoke, the twin
stays at `…-Debug` for the integration test, and both carry Microsoft's ASan runtime as
`Start-Windows.ps1` stages it locally; the Release job keeps the lane's quality gates.

**The Windows arm64 lane is a hybrid** ([`windows-arm64.yml`](../../.github/workflows/windows-arm64.yml),
2026-09-27). Flutter cannot cross-build `windows-arm64` from an x64 host
(flutter/flutter#62597), so the lane has three build jobs (and the `ort-runner-suite`
Pester job, below):
- `natives` runs `scripts/windows/Build-WindowsArm64Natives.ps1` in the hub's arm64 container
  lane. It cross-builds AccelerANTgine and `oxidant.dll`, without DirectML, because the arm64
  ORT has no DirectML EP.
- `app` builds the Flutter part natively on `windows-11-arm` against those, with clang-cl like
  every other Windows build here: `scripts/windows/Build-WindowsArm64App.ps1`. Two environment
  switches do it. `CARGOKIT_PREBUILT_DIR` is a local Cargokit patch that copies the DLL and
  skips cargo. `KATAGLYPHIS_ACCELERANTGINE_PREBUILT` makes the plugin link an imported
  AccelerANTgine instead of `add_subdirectory`.
- `app-debug` builds the same app as a Debug (ASan) one: `Build-WindowsArm64App.ps1
  -Configuration Debug`, /MD like the natives (clang-cl strips /MDd under ASan, so no debug
  CRT), the aarch64 ASan runtime staged from the runner's own VS, and the launch smoke proves
  the instrumented app starts.

With both switches unset, x64 builds exactly as before.

The lane went green in run 36322839058 and has built with clang-cl since test run 36622834879
(2026-09-29). On the device, the app tree passes the hub's import walk (40 files, 0
unresolved), and the app stays up 20 s at 147 MB with a real window. Two traps surfaced on the
way there:
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

The app job tests what it built, with the scripts the x64 lane uses:
`Invoke-FlutterTests.ps1` (the app's and the plugin's Dart suites on the arm64
Dart VM, one `TESTS:` line), `Test-KntAbi.ps1`, `Invoke-PluginGTest.ps1` (the
target `Build-WindowsArm64App.ps1` builds), and `Test-LaunchSmoke.ps1 -OrtStamp`.
Its `ort-runner-suite` job runs the Pester suite on `windows-11-arm`.
