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
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest
```

For WSL2 camera passthrough, ensure the USB device is attached before running the container.

## Windows Development

### Containerized build (Stevedore, recommended)

Windows builds run inside the `kataglyphis_beschleuniger:winamd64` image from
[Kataglyphis-ContainerHub](https://github.com/Kataglyphis/Kataglyphis-ContainerHub) — the same
image CI uses. The container engine on Windows is
[Stevedore](https://github.com/slonopotamus/stevedore) (`winget install stevedore`); apply the
post-install fixes from ContainerHub's `docs/windows-builds.md` (§ Stevedore Setup Fixes) and
always use Stevedore's bundled `docker.exe`, not `nerdctl`:

```powershell
$docker = "$env:ProgramFiles\Stevedore\bin\docker.exe"
& $docker pull ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64
```

Run the build container with **process isolation**, as described in Kataglyphis-ContainerHub:
Hyper-V isolation (the Windows default) exposes only 2 logical CPUs, while `--isolation process`
gives the container the host's full CPU count (allowed because the host build ≥ the
`servercore:ltsc2025` base build). Per ContainerHub, process isolation is for `docker run` only —
never pass it to `docker build` (layer commits fail with `hcsshim::ActivateLayer 0x20`).

```powershell
& $docker run --rm --isolation process `
  --mount "type=bind,source=$PWD,target=C:\workspace" -w C:\workspace `
  ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64 `
  powershell -NoProfile -ExecutionPolicy Bypass -File C:\workspace\scripts\windows\Build-Windows.ps1 `
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
> fsutil devdrv setfiltersallowed bindFlt, wcifs
> ```
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
> robocopy D:\GitHub\Kataglyphis-Inference-Engine C:\kata-ws /E /MT:16 /XJ /XD .dart_tool build logs
> & $docker run --rm --isolation process `
>   --mount "type=bind,source=C:\kata-ws,target=C:\ws-mnt" -w C:\ws-mnt `
>   ghcr.io/kataglyphis/kataglyphis_beschleuniger:winamd64 `
>   powershell -NoProfile -ExecutionPolicy Bypass -File C:\ws-mnt\scripts\windows\Build-Windows.ps1 `
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

> **ContainerHub submodule pin:** `scripts/windows/Build-Windows.ps1` imports PowerShell modules
> (`WindowsToolchain.Common.psm1`, `WindowsFlutter.Common.psm1`, …) from the
> `ExternalLib/Kataglyphis-ContainerHub` submodule. Newer ContainerHub `main` removed these
> modules, so keep the submodule at the commit recorded by this repo
> (`git submodule update ExternalLib/Kataglyphis-ContainerHub`) when building.

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
| `lld-link ... mismatch detected for 'RuntimeLibrary'` (Debug preset) | `ProjectOptions.cmake` defaults **ASAN ON** for clang-cl Debug (the repo's `windows/CMakePresets.json` Debug preset doesn't pin it); ASAN pulls `/MT` into objects Flutter compiles with `/MD` | Set `myproject_ENABLE_SANITIZER_ADDRESS`/`_UNDEFINED` to `OFF` in the Debug preset (needs an upstream decision for Debug+ASAN+Flutter). |
| `lld-link ... mismatch for 'annotate_string'` on `kataglyphis_libfuzzer.exe` (Debug) | Fuzz harness compiles with ASAN string annotations; prebuilt `clang_rt.fuzzer` has them off | Set `BUILD_TESTING: FALSE` for the Debug preset, or fix the fuzz target's compile defines upstream. |
| Only one preset's artifacts survive a multi-preset build | **All** presets install into the same `build\windows\x64\runner\x64-ClangCL-Windows-Release\` (the layout ignores the preset for the install prefix) | Copy the runner dir away between presets, or fix `Resolve-KataglyphisWindowsLayout`/`Windows.BuildConfig.ps1` to use per-preset install prefixes. |
| App exits with `STATUS_DLL_NOT_FOUND` (−1073741515) on a host without GStreamer/ONNX installs | The native plugin links GStreamer + ONNX Runtime, provided by `C:\runtime` in the container, `C:\Program Files\gstreamer` + `C:\onnxruntime` on a provisioned host | Stage from the image into the runner: `C:\runtime\bin\*.dll` and `C:\runtime\lib\onnxruntime-source\bin\*.dll` (onnxruntime + DirectML) → `runner\...\bin\`; `C:\runtime\lib\gstreamer-1.0\` → `runner\...\lib\gstreamer-1.0\` (GStreamer locates plugins relative to its core DLL). `Start-Windows.ps1` puts `runner\bin` on `PATH`. |
| `git init/clone/checkout` fails with `could not write config file` / `unable to write new index file` inside the container | Same `wcifs` rename/create flakiness in layer dirs | Do git surgery outside the layer zone (fresh `C:\` dirs work), or `git archive | tar -x` trees into place; a bind-mounted workspace avoids it entirely. |
| `docker run --mount` fails: `hcs::CreateComputeSystem ... Die Anforderung wird nicht unterstützt` although the source is plain NTFS | The mount **target** already exists in the image (e.g. baked `C:\workspace`) — refused on skewed hosts | Mount to a path that does not exist in the image (e.g. `target=C:\ws-mnt`) and pass `-w C:\ws-mnt`. |

### Standard build

```powershell
powershell -ExecutionPolicy Bypass -File .\add-gstreamer-to-path.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build-windows.ps1
```

### Build with custom workspace

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\build-windows.ps1 -WorkspaceDir "C:\GitHub\Kataglyphis-Inference-Engine"
```

### Fully configured build

```powershell
.\build.ps1 `
  -WorkspaceRoot "E:\flutter-project" `
  -BuildType Release `
  -Architecture x64 `
  -CMakeGenerator "Ninja" `
  -SkipFormatCheck `
  -CleanBuild $true
```

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