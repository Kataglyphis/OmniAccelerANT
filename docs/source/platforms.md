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