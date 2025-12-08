# Platform Guides

Detailed instructions for building and running on different targets.

3. Launch the Flutter web target for rapid iteration:
   ```bash
   flutter run -d web-server --profile --web-port 8080 --web-hostname 0.0.0.0
   ```

## Container Setup

Containerization keeps dependencies reproducible. A pre-built container image is available on [ContainerHub](https://github.com/Kataglyphis/Kataglyphis-ContainerHub/pkgs/container/kataglyphis_beschleuniger).

```bash
docker run -it --rm \
  -v "$(pwd)":/workspace \
  -p 9090:9090 \
  -p 8443:8443 \
  -p 8444:8444 \
  -p 5173:5173 \
  --device=/dev/video0 \
  docker pull ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest
```

> **NOTE for WSL2:** The `--device=/dev/video0` flag is required to pass USB cameras through to Docker.

## Windows Development

Windows builds rely on [clang-cl](https://clang.llvm.org/docs/MSVCCompatibility.html) to avoid MSVC dependencies.

### CMake Adjustments

Update the Flutter-generated CMake project to relax warnings and silence unused helper code:

```cmake
# Comment out
# target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")

# Add
target_compile_options(${TARGET} PRIVATE /W3 /WX /wd4100 -Wno-cast-function-type-mismatch -Wno-unused-function)
```

### Build Commands

Adjust the paths to match your environment:

```powershell
cd rust
cargo build --release
cp rust\target\release\rust_lib_kataglyphis_inference_engine.dll build\windows\x64\plugins\rust_lib_kataglyphis_inference_engine

cmake C:\GitHub\Kataglyphis-Inference-Engine\windows `
  -B C:\GitHub\Kataglyphis-Inference-Engine\build\windows\x64 `
  -G "Ninja" `
  -DFLUTTER_TARGET_PLATFORM=windows-x64 `
  -DCMAKE_CXX_COMPILER="C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\Llvm\bin\clang-cl.exe" `
  -DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-windows-msvc

cmake --build C:\GitHub\Kataglyphis-Inference-Engine\build\windows\x64 `
  --config Release `
  --target install `
  --verbose
```

## Raspberry Pi

Run GStreamer commands **outside** Docker for Pi devices.

```bash
gst-launch-1.0 \
  libcamerasrc ! video/x-raw,width=640,height=360,format=NV12,interlace-mode=progressive ! \
  x264enc speed-preset=1 threads=1 byte-stream=true ! \
  h264parse ! \
  webrtcsink signaller::uri="ws://0.0.0.0:8444" name=ws meta="meta,name=gst-stream"
```

Rotate the stream if the camera is mounted upside-down:

```bash
gst-launch-1.0 \
  libcamerasrc ! video/x-raw,width=640,height=360,format=NV12,interlace-mode=progressive ! \
  videoflip method=rotate-180 ! \
  x264enc speed-preset=1 threads=1 byte-stream=true ! \
  h264parse ! \
  webrtcsink signaller::uri="ws://0.0.0.0:8444" name=ws meta="meta,name=gst-stream"
```

Use VP8/VP9 when hardware encoders are limited:

```bash
GST_DEBUG=3 gst-launch-1.0 \
  libcamerasrc ! video/x-raw,format=RGB,width=640,height=360,framerate=30/1 ! \
  videoflip method=rotate-180 ! \
  videoconvert ! video/x-raw,format=I420 ! queue ! \
  vp8enc deadline=1 threads=2 ! queue ! \
  webrtcsink signaller::uri="ws://0.0.0.0:8443" name=ws meta="meta,name=gst-stream"
```

`deadline=0` prioritizes speed, `deadline=1` maximizes quality.

## Web Build

Enable Rust features required for the WebAssembly build:

```bash
# Windows
rustup component add rust-src --toolchain nightly-x86_64-pc-windows-msvc
rustup target add wasm32-unknown-unknown
```

Build the WASM binding with shared memory support:

```bash
flutter_rust_bridge_codegen build-web \
  --wasm-pack-rustflags "-Ctarget-feature=+atomics -Clink-args=--shared-memory -Clink-args=--max-memory=1073741824 -Clink-args=--import-memory -Clink-args=--export=__wasm_init_tls -Clink-args=--export=__tls_size -Clink-args=--export=__tls_align -Clink-args=--export=__tls_base" \
  --release
```

Serve the web build with the required COOP/COEP headers:

```bash
flutter run \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp
```

Verify the WASM headers:

```bash
curl -I http://localhost:8080/pkg/rust_lib_kataglyphis_inference_engine_bg.wasm 2>/dev/null | grep -i "cross-origin\|content-type"
```
