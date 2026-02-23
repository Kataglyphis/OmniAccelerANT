# Getting Started

This guide takes you from clone to a working local setup.

## 1) Prerequisites

- Flutter SDK and Dart in `PATH`
- Rust toolchain (`rustup`, `cargo`)
- Docker (optional but recommended for reproducible setup)
- GStreamer runtime and tools (`gst-launch-1.0`)

### Verify your tooling

```bash
flutter --version
dart --version
cargo --version
gst-launch-1.0 --version
```

## 2) Clone the repository

```bash
git clone --recurse-submodules --branch develop git@github.com:Kataglyphis/Kataglyphis-Inference-Engine.git
cd Kataglyphis-Inference-Engine
```

If you cloned without submodules:

```bash
git submodule update --init --recursive
```

## 3) Optional: camera checks on Linux

List available camera devices:

```bash
for dev in /dev/video*; do
  echo "Testing $dev"
  gst-launch-1.0 -v v4l2src device=$dev ! fakesink
done
```

Inspect resolutions/framerates:

```bash
sudo apt update
sudo apt install -y v4l-utils
v4l2-ctl --device=/dev/video0 --list-formats-ext
```

## 4) Run the app (web profile)

```bash
flutter run -d web-server --profile --web-port 8080 --web-hostname 0.0.0.0
```

Open `http://127.0.0.1:8080` in your browser.

## 5) Build API docs

```bash
bash scripts/linux/generate-docs.sh
```

Serve generated docs locally:

```bash
dart pub global activate dhttpd
export PATH="$PATH:$HOME/.pub-cache/bin"
dhttpd --path doc/api --host 127.0.0.1 --port 8080
```

## 6) WSL2 USB passthrough (if needed)

```bash
usbipd list
usbipd attach --wsl --busid 1-1.2
lsusb
```

## Next Steps

- Continue with [Platforms](platforms.md) for target-specific builds.
- Continue with [Camera Streaming](camera-streaming.md) for WebRTC pipelines.