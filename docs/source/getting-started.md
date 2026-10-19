# Getting Started

Only want ObservANT? Every [release](https://github.com/Kataglyphis/OmniAccelerANT/releases)
carries it as a package (`.deb`, AppImage, flatpak, tarball, Windows MSI) with a `SHA256SUMS`;
[a new camera in five steps](camera-streaming.md#installing-it) installs one, with or without
sudo. Building one yourself is a single script:
[Camera Streaming](camera-streaming.md#the-observant-package), *The ObservANT package*.

## 1) Prerequisites

**Or skip them:** every Linux CI lane runs in the family image
`ghcr.io/kataglyphis/kataglyphis_beschleuniger:latest`, which carries Flutter, Rust, GStreamer
and ONNX Runtime (the Windows lanes use its `:winamd64` twin).
[AGENTS.md § 5](../../AGENTS.md#5-build-run-test), *The Dart gate in 23 seconds*, runs the tests
in it with nothing installed on the host. The clone below needs no GitHub account: every URL is
HTTPS.

On the host:

- Flutter SDK and Dart in `PATH`
- Rust toolchain (`rustup`, `cargo`)
- Docker (optional, recommended for a reproducible setup); on Windows, install
  [Stevedore](https://github.com/slonopotamus/stevedore) and build with its bundled `docker.exe`
  and `--isolation process` ([Platforms](platforms.md), ANTfrastructure)
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
git clone --recurse-submodules --branch develop https://github.com/Kataglyphis/OmniAccelerANT.git
cd OmniAccelerANT
```

If you cloned without submodules:

```bash
git submodule update --init --recursive
```

## 3) Build the app, as CI does

From the README (2026-10-19). **Every lane runs containerized except the Windows arm64 app
build, which runs natively on `windows-11-arm`, and a local run invokes the same script CI
invokes**; commands, presets and switches: [AGENTS.md § 5](../../AGENTS.md#5-build-run-test).

| Lane | What CI runs | Locally |
|---|---|---|
| Windows (amd64) | `scripts/windows/Build-Windows.ps1` | the same script, in the same image |
| Linux native (amd64 / arm64) | `scripts/linux/ci/ci-container-run-native-linux.sh` | `Invoke-LinuxLane.ps1` |
| Android | `scripts/linux/ci/ci-container-run-android.sh` | `Invoke-LinuxLane.ps1 -Lane android` |
| Web | `scripts/linux/ci/ci-container-run-web-linux.sh` | `Invoke-LinuxLane.ps1 -Lane web` |

The Linux entries run through ANTfrastructure's `run-in-linux-container` action in CI and
Rancher Desktop's `nerdctl` locally; inside the container both are identical, down to the
argument list. Reproduce a CI failure locally before pushing.

The native Linux lane takes an opt-in linker, `Invoke-LinuxLane.ps1 -Env KATAGLYPHIS_LINKER=lld`
(or `mold`), off in CI; what each buys: [`project-operations.md`](project-operations.md) § *The
Linux lanes, run locally*.

A local Linux lane on a Windows host needs Rancher Desktop's engine, the repo's drive visible to
*containerd's own* mount namespace, and QEMU binfmt registered for an arm64 run. Fixes:
[`project-operations.md`](project-operations.md) § *The Linux lane, locally*; the reasoning is
ANTfrastructure's
[`rancher-desktop-linux-containers.md`](https://github.com/Kataglyphis/ANTfrastructure/blob/develop/docs/rancher-desktop-linux-containers.md).
The last two are lost on a VM restart, and silently: you get a bind mount that resolves and is
empty, or an arm64 container running x86-64 binaries.

## 4) Optional: camera checks on Linux

List available camera devices:

```bash
for dev in /dev/video*; do
  echo "Testing $dev"
  gst-launch-1.0 -q v4l2src device="$dev" num-buffers=1 ! fakesink && echo "  delivers frames"
done
```

A Raspberry Pi camera does not show up this way; `rpicam-hello --list-cameras` lists it.

Inspect resolutions/framerates:

```bash
sudo apt update
sudo apt install -y v4l-utils
v4l2-ctl --device=/dev/video0 --list-formats-ext
```

## 5) Run the app (web profile)

The web build needs `web/sqlite3.wasm`. It is committed; this refreshes it:

```bash
bash third_party/ANTfrastructure/linux/scripts/05-frameworks/flutter/setup-sqlite3-wasm.sh .
```

The fetcher lives in ANTfrastructure, not in a per-app copy, and reads the version and its SHA256
from ANTfrastructure's `versions.env`. The download is checksum-verified, so a tampered,
truncated or *wrong-version* asset fails here, not in a browser. It happened: the copy that was
committed did not match the version the script claimed to fetch.

It also wants `web/pkg/`, the Rust core built for wasm (generated, gitignored): without it the
page waits 20 s for the core, then starts without it, and only the About page's Rust demo is
missing. Build it as [`platforms.md`](platforms.md) § *Web Build (WASM)* shows, then run with
the COOP/COEP headers that page names (Firefox and Safari need them to load the core):

```bash
flutter run -d web-server --profile --web-port 8080 --web-hostname 0.0.0.0 \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp
```

Open `http://127.0.0.1:8080`.

## 6) Build API docs

```bash
bash scripts/linux/generate-docs.sh
```

Serve generated docs locally:

```bash
dart pub global activate dhttpd
export PATH="$PATH:$HOME/.pub-cache/bin"
dhttpd --path doc/api --host 127.0.0.1 --port 8080
```

**By hand, without the script** (from the README, 2026-10-19): `scripts/windows/Build-Windows.ps1`
does this as its "Generate API Docs" step (skip it with `-SkipDocs`). Generate the site into
`doc/api` with the pub-activated `dartdoc`, **not** the SDK-bundled `dart doc`: dartdoc 9.0.4
(bundled with several Flutter SDKs, the Windows build image's among them before it moved to
Flutter 3.47.4) crashes on any Flutter app with a `_stripDocImports` RangeError; ≥ 9.0.9 fixes
it. Both images now carry the Flutter the hub pins (`FLUTTER_VERSION` in its `versions.env`,
3.47.7 at this pin), whose bundled `dart doc` the Linux lane's `generate-docs.sh` runs without
trouble.

```bash
dart pub global activate dartdoc      # pulls >= 9.0.9
dart pub global run dartdoc --output doc/api
```

On PowerShell, the pub-cache `bin` goes on `PATH` like this:

```powershell
$env:Path += ";$env:USERPROFILE\AppData\Local\Pub\Cache\bin"
```

Serve it with `dhttpd` as above, then open <http://127.0.0.1:8080>.

## 7) WSL2 USB passthrough (if needed)

In Windows PowerShell (bus ids change between plug-ins):

```powershell
usbipd list
usbipd attach --wsl --busid 1-1.2
```

Then in WSL, `sudo modprobe uvcvideo` makes it `/dev/video0` (`lsusb` shows it). WebRTC to a
browser also needs `networkingMode=mirrored` in `%USERPROFILE%\.wslconfig`; both are gone after a
WSL restart ([AGENTS.md § 4](../../AGENTS.md#4-pitfalls-specific-to-this-project)).

## Next Steps

- [Platforms](platforms.md): target-specific builds.
- [Camera Streaming](camera-streaming.md): WebRTC pipelines.
