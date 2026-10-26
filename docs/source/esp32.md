# ESP32-S3 companion and camera

An ESP32-S3 on the native USB port is OmniAccelerANT's physical companion: a USB peripheral, not
a second app. Two firmware variants speak the same framed USB protocol:

| Variant | On the board | Source |
| --- | --- | --- |
| **Companion** | Rust (`esp-hal`): USB, LED/button, telemetry, host-detection notifications | `firmware/esp32-s3` |
| **Camera** (ESP32-S3-EYE) | ESP-IDF + ESP-WHO/ESP-DL cat detection (C/C++) **plus** a Rust protocol `staticlib` | `firmware/esp32-s3-eye` |

The companion was the original bring-up; the camera firmware and its on-device AI are in
[Camera and on-device AI](#camera-and-on-device-ai).

## What runs where, in plain terms

The Flutter application does **not** run on the ESP32: it stays on the host (a Windows/Linux PC
or a Raspberry Pi), and the board runs only a firmware. The USB cable is the whole connection:
no Wi-Fi, no driver installation, no web server on the board.

```
 ESP32-S3 companion (Rust)                 Host (OmniAccelerANT)
 ┌───────────────────────────┐   USB CDC  ┌──────────────────────────────┐
 │ GPIO0  BOOT button        │  /dev/tty  │ Rust link  → frb → Device    │
 │ GPIO2  status LED         │  ACM0/COMx │ page (Flutter)               │
 │ Hello, telemetry, pong    │ ◄────────► │ webcam engine ──► detections │
 └───────────────────────────┘   frames   └──────────────────────────────┘

 ESP32-S3-EYE camera (ESP-IDF)             Host (same link)
 ┌───────────────────────────┐   USB CDC  ┌──────────────────────────────┐
 │ OV2640 → ESP-DL cat model │  /dev/tty  │ CameraDetection → Device page│
 │ Rust protocol staticlib   │  ACM0/COMx │ (count, best score)          │
 └───────────────────────────┘   frames   └──────────────────────────────┘
```

1. **Plug in.** The chip's built-in USB peripheral is a plain serial port (`/dev/ttyACM0`,
   `COMx`); nothing is installed on the PC.
2. **Select and connect** on the Device page. The Rust host opens the port and sends
   `HostHello`; the board answers `Hello` (firmware version, chip, MAC). That is the handshake.
3. **Stay in touch.** The board sends telemetry about once a second (uptime, button state, last
   detection count) and answers `Ping` with `Pong`. If the host hears nothing for 6 s, it
   reports a disconnect.
4. **Control it.** The LED sliders send `SetLed`; the firmware acknowledges. The BOOT button
   sends a `Button` event back (companion).
5. **Detections.** Companion: the host's Rust webcam detector sends `Detection`, and the board
   pulses its LED. Camera firmware: the board's ESP-DL detector sends `CameraDetection`, and the
   Device page shows the count and best score. Dart is in neither path.
6. **Unplug.** The link reports the failure to the Device page; plug back in, rescan, connect.

One frame of the small, versioned protocol:

```text
A5 5A | version u8 | seq u16 LE | len u16 LE | postcard payload | CRC-16/CCITT LE
```

The CRC covers `version`, `seq`, `len` and the payload. `crates/esp32-protocol` is `no_std` and
compiles for both the host and the Xtensa target, so a message cannot drift between the ends.

## Why this shape

Three integration routes were considered:

| Route | Host side | Firmware | Verdict |
| --- | --- | --- | --- |
| **USB CDC + framed protocol** | Rust (`serialport` + shared protocol crate) | Rust (`esp-hal`) companion; ESP-IDF/ESP-DL (C/C++) + Rust staticlib camera | **Chosen.** Plug-and-play, no network or drivers, both ends share one protocol crate. |
| USB UVC camera | existing GStreamer path | C (ESP-IDF UVC) | The board is a companion, not a UVC camera; the useful Rust surface shrinks to "the existing pipeline". |
| Wi-Fi / WebRTC producer | existing ObservANT path | C or Rust | Needs credentials, DHCP, signalling and a camera; the board is plugged in by USB and has none of those. |

| Direction | Message | Purpose |
| --- | --- | --- |
| host → device | `HostHello` | version handshake, retried every 500 ms until `Hello` |
| device → host | `Hello` | protocol, firmware, chip, MAC, uptime |
| both | `Ping` / `Pong` | liveness and a UI-visible round trip |
| host → device | `SetLed` | RGB collapsed to on/off, optional blink |
| host → device | `Detection` | host webcam's latest count and score, throttled |
| device → host | `CameraDetection` | the board's own ESP-DL camera count and best score |
| host → device | `SetTelemetryPeriod` | 0 stops periodic telemetry |
| device → host | `Telemetry` | uptime, heap, temperature, button, last count |
| device → host | `Button` | BOOT button edge and press count |
| both | `Ack` / `Error` | command outcome |

## Hardware

- **Companion:** ESP32-S3 DevKitC-1, or any board exposing the native USB peripheral; 8 MB flash
  is the tested size. BOOT button GPIO0 (active low), status LED GPIO2. The DevKitC-1's onboard
  WS2812 is **not** driven: it needs a data protocol, and a plain GPIO is portable. Wire an LED
  to GPIO2 (with a resistor) or change the two pin numbers in `firmware/esp32-s3/src/main.rs`.
- **Camera:** ESP32-S3-EYE: 8 MB flash, **8 MB octal PSRAM**, OV2640 on the DVP bus, LCD,
  ES8311 codec; camera/SCCB/DVP pins in [Camera and on-device AI](#camera-and-on-device-ai).
  The Rust protocol's `SetLed` targets the EYE's green LED (GPIO3), but the camera app disables
  the BSP LED helper, so there `SetLed` only tests the Ack/host→device path; the companion's
  GPIO2 is the controllable LED.
- The cable goes to the **native USB** port, not the UART bridge. The board enumerates as
  `303a:1001`, `USB JTAG/serial debug unit`, usually `/dev/ttyACM0` (`COMx` on Windows); its USB
  serial number is the MAC.
- `esp-hal` 1.2.2 does not expose the internal temperature sensor, so the companion's telemetry
  reports `0` and the app shows `—`. The camera firmware reports `0` too.

## Build and flash the companion firmware

The toolchain is Espressif's Xtensa Rust fork (1.97), installed by `espup`, on aarch64 and x86_64
Linux. Keep it under `$HOME`: `/tmp` is often a small tmpfs (§ *Troubleshooting*). This section is
the companion; the camera firmware's build is in [Camera and Rust protocol
firmware](#camera-and-rust-protocol-firmware-integrated).

```bash
# On the host, once:
#   espup install --targets esp32s3
#   install the prebuilt espflash binary
# Then:
firmware/esp32-s3/flash.sh                    # /dev/ttyACM0, native USB
ESP32_PORT=/dev/ttyUSB0 firmware/esp32-s3/flash.sh   # UART bridge, default reset
```

The host flash script and the camera build script both source
`scripts/linux/lib/espup-env.sh`. It prefers `$ESPUP_HOME/export.sh` (default:
`~/.cache/kataglyphis-esp/export.sh`), sets `RUSTUP_HOME`, `CARGO_HOME` and `PATH`
for that toolchain, and falls back to `~/export-esp.sh`. A missing export file exits
with status 2. `bash scripts/linux/tests/test-espup-env.sh` checks both routes and
the missing-toolchain error without a board.

The same build runs in the family image, with the toolchain in a named volume:

```bash
scripts/linux/esp32/build-firmware.sh                 # build only
scripts/linux/esp32/build-firmware.sh --flash         # build + flash /dev/ttyACM0
scripts/linux/esp32/build-firmware.sh --flash --port /dev/ttyUSB0 --uart
```

- The volume keeps `espup`, the Xtensa toolchain, `espflash`, the cargo registry and `target/`
  between runs; sources stay on the host mount. The first run needs network, later runs are
  offline.
- **Commit the OxidANT submodule before moving this repository's gitlink.** The firmware's only
  path dependency is `third_party/OxidANT/crates/esp32-protocol`; a clean checkout whose gitlink
  predates that crate cannot resolve the firmware build.
- The build runs as the image user. Only `espflash` runs as root, because rootless nerdctl
  remaps `/dev/ttyACM0` to `nobody:nogroup`, which the image user cannot open; the build
  artifacts stay owned by the image user.
- `firmware/esp32-s3/Cargo.lock` is committed: `--locked` makes the volume build reproducible.
  The firmware is a separate crate with its own `rust-toolchain.toml` (`channel = "esp"`), not a
  member of OxidANT's workspace and not built by the app's Cargokit path.

## App side

`kataglyphis_esp32` (OxidANT `crates/esp32`) owns discovery, framing and two threads:

- the **reader** parses frames, answers `Ping`, sends `HostHello` until the handshake and
  reports a 6 s silence as a disconnect;
- the **writer** owns the port and drains a channel, so the inference thread never blocks on
  USB.

It is a **desktop-only target dependency** of `oxidant`:

```toml
[target.'cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))'.dependencies]
kataglyphis_esp32 = { path = "crates/esp32" }
```

Android and wasm builds do not compile `serialport`; `esp32_available()` returns `false` there.
On Linux `serialport` is built **without** its optional libudev feature: port discovery uses its
`/sys/class/tty` fallback, so no new native library enters the packaged bundle and the riscv64
cross lane is unaffected.

The frb surface is `src/api/esp32.rs`:

| Dart | Rust |
| --- | --- |
| `esp32Available()` | compile-time desktop answer |
| `esp32ListDevices()` | Espressif-first USB port list |
| `esp32Connect(path)` | opens the link, returns an event `Stream` |
| `esp32Disconnect()` | stops both threads |
| `esp32Connected()` | handshake state |
| `esp32SetLed(...)` | `SetLed` |
| `esp32Ping()` | `Ping` with a fresh id |
| `esp32SetTelemetryPeriod(ms)` | telemetry cadence |
| `esp32NotifyDetection(count, score)` | external/manual detection forwarding |

The **Device** page (`lib/Pages/DevicePage/`) shows the port, firmware, MAC, uptime, heap,
temperature, button, the latest host-webcam detection count, the LED sliders and a ping; with
the camera firmware, also **On-device camera** (count and best score) once the first `camera`
event arrives. It is a view over `Esp32Controller`; `Esp32Api` is the seam the tests fake, so
`flutter test` needs no Rust library.

`Esp32Event.kind == "camera"` carries the board's own detector: `value` is the hit count,
`scorePermille` the best score (0–1000). The companion never sends it, so the field stays hidden
there.

### Detections without Dart

`webcam_engine`'s `EngineConfig` has `on_detections`; `api/webcam.rs` installs
`api::esp32::notify_detections`, so every inference result is offered to the link on the
inference thread. `Link::notify_detection` throttles: a change at most every 100 ms, a steady
count every 250 ms, zero every second. The firmware pulses GPIO2 for 120–300 ms depending on the
score. No Dart code runs on this path.

`esp32NotifyDetection` is for sources outside the Rust webcam engine, such as the ObservANT web
page.

The camera firmware reports the other direction: its ESP-DL detector calls
`omni_proto_on_detections`, and the Rust task sends `CameraDetection` to the host. The Device
page renders the count and best score, **not** the boxes: the ESP-WHO LCD app can draw them, but
the integrated firmware uses the terminal variant and the message carries count/score only. The
host webcam path above is unchanged.

## Camera and on-device AI

**Status 2026-10-18: the integrated camera firmware is built and flashed.** Variant A (true
on-device AI) runs on the ESP32-S3-EYE; the companion (`firmware/esp32-s3`) remains the
fallback. The camera firmware is a separate ESP-IDF project because it needs
`esp32-camera`/ESP-DL; the Rust protocol is a staticlib inside it.

### Probe result

`firmware/esp32-s3-probe` replaces the companion for one boot, reports PSRAM and scans the
camera's SCCB bus. On this board:

| Item | Result |
| --- | --- |
| Board | **ESP32-S3-EYE** (8 MB flash, **8 MB octal PSRAM**) |
| Camera | **OV2640**, SCCB address `0x30`, PID `0x26`, VER `0x42` |
| SCCB | SDA GPIO4, SCL GPIO5 (the ES8311 codec also answers at `0x12` on this bus) |
| XCLK | GPIO15; the sensor answered only after a clean **10 MHz** LEDC clock |
| DVP | VSYNC 6, HREF 7, PCLK 13, Y2…Y9 = 11, 9, 8, 10, 12, 18, 17, 16 |

The first scan, without XCLK, found only the codec; a busy-loop clock also missed the sensor,
and the LEDC's 10 MHz made it answer. So the probe starts the clock before scanning. The
integrated camera firmware was flashed after it.

### Camera and Rust protocol firmware (integrated)

The script builds the **integrated firmware**: Espressif's ESP-WHO `object_detect` example with
the `cat_detect` model (C++ camera + ESP-DL) **plus** `firmware/esp32-s3-eye/rust_protocol`, a
`no_std` staticlib that owns the native USB Serial/JTAG protocol. The C++ detection callback
calls `omni_proto_on_detections`; the Rust task sends `Hello`, `Telemetry` and
`CameraDetection`, and handles `HostHello`, `Ping`, `SetLed` and `SetTelemetryPeriod`. The C++
app console is UART0, so the USB port belongs to the protocol: **`idf.py monitor` is not the
view**, it competes for the protocol port. Use the host probe or the app's Device page.

```bash
scripts/linux/esp32/build-eye-demo.sh            # build only
scripts/linux/esp32/build-eye-demo.sh --flash    # build and flash /dev/ttyACM0
```

The script clones ESP-WHO into `~/.cache/esp-who`, patches the example to the terminal app and
the esp-dl 3.3.13 API, builds the Rust staticlib on the host (espup's `esp` toolchain), copies it
into the ESP-IDF project, and builds in the official `espressif/idf:release-v5.5` image; the
family `:latest` image carries no ESP-IDF. The first build downloads the component-managed BSP,
ESP-DL and the cat model.

Model `espressif/cat_detect` (packed: `espdet_pico_224_224_cat`, 498 KB); BSP
`esp32_s3_eye_noglib` with OV2640 DVP RGB565 at 240×240, 8 MB flash and octal PSRAM; factory
app partition 8000K.

**Verified 2026-10-18** after building and flashing the integrated script: the boot log reports
`Found 8MB PSRAM device`, `Camera PID=0x26 VER=0x42`, `Detected OV2640 camera`, five PSRAM frame
buffers and the cat model loaded. The app binary is 0x2873d0 bytes (2.64 MB), leaving 68 % of
the 8000K partition free. The host probe saw firmware 0.2.0, chip Esp32S3, MAC
E8:06:90:9D:3E:78, and the events in § *Verify*.

The script pins ESP-WHO `b6ac2be`, BSP `5.0.2` and `cat_detect` `0.3.0`. Master's example code
uses the BSP 6.0.0 `bsp_camera_cfg_t` API while its lock and sdkconfig defaults are still 5.0.2;
pinning the commit before the BSP 6.0.0/`esp_video` migration avoids that mismatch. The newer
esp-dl also needs its `RGB565BE` enum, `img.bytes()`, two-argument `sw_decode_jpeg` and
non-`caps` `cvt_pix` call sites patched; the script does that. The Rust archive sits at the end
of the IDF link line, so the main component forces `esp_efuse_mac_get_default`,
`xTaskCreatePinnedToCore` and `usb_serial_jtag_driver_install` with `-Wl,--undefined`.

### What A means here

- **On the board:** ESP-IDF + the `esp32-camera` driver + ESP-DL/ESP-WHO (C/C++), because the
  optimised camera and inference code is C/C++. Rust owns the USB protocol, control and
  telemetry as a `staticlib` linked into that app: as much Rust as the vendor components allow.
- **On the host:** `kataglyphis_esp32` has the `CameraDetection` link event, shown on the Device
  page (§ *App side*). A JPEG preview is the next optional step.
- **Model:** the ESP-DL `espdet_pico_224_224_cat` detector. The 8 MB flash is tight: a 320×320
  YOLO11n model plus ESP-IDF and the Rust app does not fit comfortably; a 16 MB flash board
  would allow a larger model.
- **Expectation:** a few frames per second, not 30 fps video. Good for "a cat arrived" events,
  not for replacing the host's ONNX model.

### Seeing it

```bash
# Host probe (same events the app receives):
cd third_party/OxidANT
cargo run -p kataglyphis_esp32 --example probe

# Or rebuild the desktop app and open the Device page, then Connect.
flutter run -d linux
```

Point the camera at a cat: the probe's `camera:` line and the Device page's **On-device camera**
field change together.

### Running the probe firmware

```bash
cd firmware/esp32-s3-probe
cargo +esp build --release
espflash flash --monitor --chip esp32s3 --port /dev/ttyACM0 --before usb-reset \
  target/xtensa-esp32s3-none-elf/release/omni-esp32s3-probe
```

Then reflash the companion with `firmware/esp32-s3/flash.sh`.

## Verify

```bash
# Rust protocol + bridge (host, no board):
cargo test -p kataglyphis_esp32_proto -p kataglyphis_esp32

# End to end against a flashed board:
cargo run -p kataglyphis_esp32 --example probe
```

The probe lists the ports, opens the first Espressif board, prints `hello`, `telemetry`,
`camera`, `ack` and `pong`, pulses the LED and sends one detection. A healthy run against the
camera firmware:

```
hello: DeviceInfo { protocol: 1, firmware_major: 0, firmware_minor: 2,
                    firmware_patch: 0, chip: Esp32S3, mac: [...] }
telemetry: Telemetry { uptime_ms: 1025, free_heap: 4967415, ... }
camera: 0 hit(s), best 0 per mille
ack: command 3        # SetLed
pong: 42
```

`firmware_patch` is the camera firmware's USB Serial/JTAG driver install result (`0` =
success). The `camera` line is the on-device detector; it stays at 0 until a cat is in view.
Against the companion the line is absent and `firmware_minor` is 1.

## Troubleshooting

- **`Permission denied` on `/dev/ttyACM0`**: on the host, add your user to the device's group
  (usually `plugdev`/`dialout`). The container script already flashes as root (§ *Build and
  flash the companion firmware*).
- **`espflash` cannot connect on `/dev/ttyACM0`**: the native USB port needs
  `--before usb-reset`, a UART bridge (`/dev/ttyUSB0`) `default-reset`. The scripts pick it from
  the port name, or pass `--uart`.
- **The board reboots when the port opens**: do not toggle DTR/RTS on the native USB port; the
  probe does not.
- **The app shows "desktop builds only"**: that is the web/Android build. On Linux or Windows,
  check that the app was rebuilt with the new Rust core and that the port is in the dropdown.
- **The device is silent after flashing**: check the baud-independent USB CDC link with
  `espflash board-info`, then run the probe. The companion sends `Hello` every 500 ms until it
  sees `HostHello`, the camera firmware every 2 s; the host may be the silent side.
- **The camera is not found**: run `firmware/esp32-s3-probe` and check the camera ribbon and
  the SCCB pair (SDA4/SCL5). The OV2640's SCCB answers only with **XCLK 10 MHz on GPIO15**; a
  bare I2C scan without XCLK finds only the ES8311 codec (§ *Probe result*).
- **`camera:` stays at 0**: the on-device model reports only a cat it is sure about; check the
  lighting and point the camera at the cat. Events are throttled to one per 100 ms, not one per
  camera frame.
- **The app connects but has no "On-device camera" field**: the board runs the **companion**,
  which sends no `CameraDetection`. Flash the camera firmware with
  `scripts/linux/esp32/build-eye-demo.sh --flash`; `firmware/esp32-s3/flash.sh` restores the
  companion.
- **No `Hello` / the app stays disconnected**: the camera firmware's C++ console must be
  **UART0** (`CONFIG_ESP_CONSOLE_UART_DEFAULT`); a USB console consumes the host's `HostHello`
  before the Rust read, and `idf.py monitor` competes for the protocol port. `firmware_patch` in
  `Hello` is the USB driver install result (§ *Verify*).
- **The ESP-WHO build fails**: use the script, which carries the pins and the esp-dl and
  `-Wl,--undefined` patches (§ *Camera and Rust protocol firmware (integrated)*). Bumping the
  pin needs the code, defaults and patches moved together; the first build downloads the BSP and
  model.
- **Toolchain install fails with "No space left on device"**: `espup` was pointed at `/tmp` (a
  4 GB tmpfs on the Pi). Use `$HOME/.cache/kataglyphis-esp`.
