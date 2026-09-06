# Platform Guides

Build and run instructions by target platform.

## Container Setup (Linux/WSL)

Use the published container image for reproducible tooling:

```bash
docker run -it --rm \
  -v "$(pwd)":/workspace \
  -p 9090:9090 \
  -p 8443:8443 \
  -p 8444:8444 \
  -p 5173:5173 \
  --device=/dev/video0 \
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest-cross
```

For WSL2 camera passthrough, ensure the USB device is attached before running the container.

## Windows Development

### Containerized build (Stevedore, recommended)

Windows builds run inside the `kataglyphis_beschleuniger:winamd64` image from
[ContainerHub](https://github.com/Kataglyphis/ContainerHub) — the same
image CI uses. The container engine on Windows is
[Stevedore](https://github.com/slonopotamus/stevedore) (`winget install stevedore`); apply the
post-install fixes from ContainerHub's `docs/windows-host-setup.md` (§ A1) and
always use Stevedore's bundled `docker.exe`, not `nerdctl`:

```powershell
$docker = "$env:ProgramFiles\Stevedore\bin\docker.exe"
& $docker pull ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64
```

Run the build container with **process isolation** (`--isolation process`) — it
gives the container the host's full CPU count instead of the Hyper-V default's 2,
and must never be passed to `docker build`. The engine rationale, the CPU/base-build
caps, and the `docker build` prohibition are ContainerHub's, not this project's — see
[`windows-build-lanes.md`](../../third_party/ContainerHub/docs/windows-build-lanes.md).

```powershell
& $docker run --rm --isolation process `
  --mount "type=bind,source=$PWD,target=C:\workspace" -w C:\workspace `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64 `
  pwsh -NoProfile -ExecutionPolicy Bypass -File C:\workspace\scripts\windows\Build-Windows.ps1 `
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
> and fails with a bare syntax dump. ContainerHub owns this procedure, including the reboot
> requirement, the "allowed vs attached" distinction and how to revert it:
> `third_party/ContainerHub/docs/windows-container-build-performance.md`
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

> **ContainerHub submodule:** `scripts/windows/Build-Windows.ps1` resolves every PowerShell
> module through `scripts/windows/Resolve-BuildModule.ps1`, which looks in
> `third_party/ContainerHub/windows/scripts/modules/` first and only then in
> `scripts/windows/modules/`. Check the submodule out before building
> (`git submodule update --init --recursive third_party/ContainerHub`); a missing
> one is reported by name with that exact command. All those modules declare
> `#requires -Version 7.0`, hence `pwsh` rather than `powershell` in the commands above.

Run the app on the host after a build:

```powershell
.\scripts\windows\Start-Windows.ps1                                        # release preset (default)
.\scripts\windows\Start-Windows.ps1 -Configuration x64-ClangCL-Windows-Debug
```

### Troubleshooting containerized Windows builds (verified 2026-07-15)

| Symptom | Cause | Fix |
|---------|-------|-----|
| CMake: `Could NOT find PkgConfig` | The winamd64 image bakes `PKG_CONFIG_PATH` + `.pc` files (`C:\runtime\...`) but ships **no pkg-config binary** | `scoop install pkg-config` inside the container (there is no `pkgconf` manifest). Durable fix belongs in the ContainerHub image. |
| Cargokit: `rustup not found in PATH.` during CMake install | The Flutter plugin `rust_builder` builds its Rust crate via Cargokit, which hard-requires rustup; the image is scoop-Rust-only | In the container: `Invoke-WebRequest https://win.rustup.rs/x86_64 -OutFile C:\rustup-init.exe; C:\rustup-init.exe -y --default-toolchain stable --profile minimal`. A rustup **with** a default toolchain is safe — ContainerHub's warning targets toolchain-less rustup shims only. |
| `PathNotFoundException ... sqlite3.dll.tmp` in `flutter assemble` | Dart's `renameSync`/`copySync` fail (errno 3) in container-layer dirs **and on bind-mounted paths** on this skewed host — the sqlite3 hook downloads fine, then dies on the two-path file op | Junction `.dart_tool` and `build` to fresh **container-local** dirs (`mklink /J`, from inside the container) — Dart ops work there. Hook patching (`renameSync` → direct `openWrite` to the final name) is a fallback if junctions are impossible. |
| `lld-link ... mismatch detected for 'RuntimeLibrary'` (Debug preset) | A `/MT` override (root `CMAKE_MSVC_RUNTIME_LIBRARY`, an abseil `/MT` hack, or a C++20 module BMI built `/MT` re-emitting `detect_mismatch` into importers) collides with Flutter's `/MD` | Remove **every** `/MT` override and compile ASAN with `/clang:-shared-libsan` so clang emits dynamic-CRT link directives. All wired up in the inference core's `third_party/AccelerANTgine/cmake/` and its `third_party/CMakeLists.txt`. Diagnose stray directives with `llvm-readobj --coff-directives <obj>`. |
| Instrumented app dies instantly `STATUS_ENTRYPOINT_NOT_FOUND` (−1073741511) | The staged `clang_rt.asan_dynamic-x86_64.dll` is LLVM's, but the binary's baked-in thunk imports Microsoft-named allocator forwarders (`__asan_new`, `__asan_delete`, …), or vice-versa | Link **and** stage a matched pair. The Debug preset links Microsoft's thunk+import lib (`cmake/Sanitizers.cmake` points the link-search at `VC\Tools\MSVC\<ver>\lib\x64`); `Start-Windows.ps1` stages the matching `clang_rt.asan_dynamic-x86_64.dll` from the same MSVC dir. |
| Instrumented app aborts on startup with `bad-free` / `bad-malloc_usable_size` | LLVM's ASan runtime loads after ucrtbase, so CRT/COM startup allocations are unhooked and abort when freed through interceptors | Use **Microsoft's** ASan runtime (VS BuildTools) — it tracks Windows heap ownership and passes foreign frees through — plus `ASAN_OPTIONS=alloc_dealloc_mismatch=0:check_malloc_usable_size=0`. This is the shipped Debug-preset config; the full app runs clean under it. |
| Only one preset's artifacts survive a multi-preset build | **All** presets install into the same `build\windows\x64\runner\x64-ClangCL-Windows-Release\` (the layout ignores the preset for the install prefix) | Copy the runner dir away between presets, or fix `Resolve-KataglyphisWindowsLayout`/`Get-WindowsBuildConfig.ps1` to use per-preset install prefixes. |
| App exits with `STATUS_DLL_NOT_FOUND` (−1073741515) on a host without GStreamer/ONNX installs | The native plugin links GStreamer + ONNX Runtime, provided by `C:\runtime` in the container, `C:\Program Files\gstreamer` + `C:\onnxruntime` on a provisioned host | Stage from the image into the runner: `C:\runtime\bin\*.dll` and `C:\runtime\lib\onnxruntime-source\bin\*.dll` (onnxruntime + DirectML) → `runner\...\bin\`; `C:\runtime\lib\gstreamer-1.0\` → `runner\...\lib\gstreamer-1.0\` (GStreamer locates plugins relative to its core DLL). `Start-Windows.ps1` puts `runner\bin` on `PATH`. |
| `git init/clone/checkout` fails with `could not write config file` / `unable to write new index file` inside the container | Same `wcifs` rename/create flakiness in layer dirs | Do git surgery outside the layer zone (fresh `C:\` dirs work), or `git archive | tar -x` trees into place; a bind-mounted workspace avoids it entirely. |
| `docker run --mount` fails: `hcs::CreateComputeSystem ... Die Anforderung wird nicht unterstützt` although the source is plain NTFS | The mount **target** already exists in the image (e.g. baked `C:\workspace`) — refused on skewed hosts | Mount to a path that does not exist in the image (e.g. `target=C:\ws-mnt`) and pass `-w C:\ws-mnt`. |
| `docker commit` (or `docker start` of a stopped container) fails `hcsshim::ActivateLayer ... (0x20)` | The container was created with `--isolation process`; on this host its writable layer stays locked after stop and cannot be snapshotted | Create any container you intend to **commit** with `--isolation hyperv` (kept-alive + `docker exec` build + stop + commit works — this is why the ContainerHub orchestrator uses hyperv for run+commit). `docker export` is **not** a workaround (the daemon refuses to export Windows containers). Reserve `--isolation process` for throwaway runs whose output you extract *live* via `tar` over `docker exec` before stopping. |
| `mediafoundation` plugin registers "0 features" / `gst-inspect mfvideosrc` says "no such element"; debug shows `MFStartup` → `0x80004001` (E_NOTIMPL) | The build image's **Server Core** base ships no Media Foundation platform — copying `mfplat.dll`/`mf.dll` doesn't help (the `Server-Media-Foundation` feature is *Removed* with no servicing source; `Install-WindowsFeature` fails `0x800f0916`) | **Not a build defect.** `gstmediafoundation.dll` compiles, links, and loads correctly; it only registers `mfvideosrc` on a **Windows client host** (Win10/11) where MF is present. Verify the webcam source on the host, never in-container (which also has no camera). The Rust capture path auto-falls back `mfvideosrc → ksvideosrc → autovideosrc`, so `ksvideosrc` covers hosts without MF. |
| CMake configure: `add_subdirectory ... .plugin_symlinks/kataglyphis_native_inference/windows which is not an existing directory` (only this one plugin) | `Fix-FlutterPluginSymlinks` **copies** each plugin dir into `.plugin_symlinks`; for `kataglyphis_native_inference` the recursive copy of its deep `native/AccelerANTgine/third_party/*` tree overruns the 260-char path limit and aborts before `windows\` is copied, leaving a broken junction. Since 2026-09-05 that tree is no longer inside the plugin — the inference core is a sibling submodule at `third_party/AccelerANTgine` and the plugin directory is 97 files — so a copy would no longer overrun; the junction stays regardless, as the cheaper and more robust option | Use a **junction** (`mklink /J`) rather than a copy for container-local workspaces — immune to MAX_PATH (the "copy avoids symlink access-denied" rationale only applies to bind-mounted paths). Clear stale `windows\flutter\ephemeral` + `.dart_tool` first: a broken junction from a prior run makes `flutter build --config-only` crash `PathExistsException` (errno 183, "already exists"). |
| App window flashes then exits on the host (~6 MB, no window title) | The native C++ plugin can't load its dependency `AccelerANTgine.dll` — the build leaves it in a `bin\` **subdirectory** of the runner, not beside the exe — and the VC++ runtime isn't bundled | Copy `runner\...\bin\AccelerANTgine.dll` next to the exe, and stage the VC++ redist CRT DLLs (`VC\Redist\MSVC\*\x64\*.CRT\*.dll`, or `msvcp140.dll`/`vcruntime140*.dll` from `System32`). A fully-initialized app is ~130 MB with a real window handle. `Start-Windows.ps1` / the MSIX layout should place `AccelerANTgine.dll` beside the exe. |

### Standard build

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\Build-Windows.ps1
```

`pwsh`, not `powershell`: every ContainerHub module declares
`#requires -Version 7.0`. GStreamer needs no PATH preamble — the image bakes
`PKG_CONFIG_PATH` and the runtime DLLs.

### Build with custom workspace

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\Build-Windows.ps1 -WorkspaceDir "C:GitHubOmniAccelerANT"
```

### Selected presets, no MSIX

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\Build-Windows.ps1 `
  -Configurations "clangcl-debug,clangcl-release" `
  -SkipMsixPackaging
```

`Build-Windows.ps1 -?` lists the rest. CI passes only `-SkipMsixPackaging`, so
that invocation is the parity run — see AGENTS.md § 4.

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

Enable required Rust targets/components and build web bindings:

```bash
rustup component add rust-src
rustup target add wasm32-unknown-unknown

flutter_rust_bridge_codegen build-web \
  --wasm-pack-rustflags "-Ctarget-feature=+atomics -Clink-args=--shared-memory -Clink-args=--max-memory=1073741824 -Clink-args=--import-memory -Clink-args=--export=__wasm_init_tls -Clink-args=--export=__tls_size -Clink-args=--export=__tls_align -Clink-args=--export=__tls_base" \
  --release
```

Run Flutter web with COOP/COEP headers:

```bash
flutter run \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp
```