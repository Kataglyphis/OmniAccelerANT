# ESP32-S3 companion and camera

An ESP32-S3 on the native USB port is OmniAccelerANT's physical companion. Two firmware
variants speak the same framed USB protocol:

| Variant | On the board | Source |
| --- | --- | --- |
| **Companion** | Rust (`esp-hal`): USB, LED/button, telemetry, host-detection notifications | `firmware/esp32-s3` |
| **Camera** (ESP32-S3-EYE) | ESP-IDF + ESP-WHO/ESP-DL cat detection (C/C++) **plus** a Rust protocol `staticlib` | `firmware/esp32-s3-eye` |

The Flutter application stays on the host; the board is a USB peripheral, not a second
app. This page starts with the companion (the fallback and the original bring-up), then
covers the camera firmware and the on-device AI.

## What runs where, in plain terms

The Flutter application does **not** run on the ESP32. OmniAccelerANT stays on the
host (a Windows/Linux PC or a Raspberry Pi); the board runs only a firmware. The USB
cable is the whole connection — no Wi-Fi, no driver installation and no web server on
the board.

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

1. **Plug in.** The chip's built-in USB peripheral makes the board look like a normal
   serial port (`/dev/ttyACM0`, `COMx`). Nothing is installed on the PC for this.
2. **Select and connect** on the app's Device page. The Rust host opens the port and
   sends a small `HostHello`; the board answers with `Hello` (firmware version, chip,
   MAC). That is the handshake.
3. **Stay in touch.** The board sends telemetry about once a second (uptime, button
   state, last detection count) and answers a `Ping` with `Pong`. If the host hears
   nothing for six seconds, it reports a disconnect.
4. **Control it.** The LED sliders send `SetLed`; the firmware acknowledges. Pressing
   the BOOT button sends a `Button` event back (companion).
5. **Detections.** With the **companion**, the host's Rust webcam detector sends
   `Detection` to the board, which pulses its LED. With the **camera** firmware, the
   board's own ESP-DL detector sends `CameraDetection` to the host; the Device page
   shows the count and best score. Dart is not in either detection path.
6. **Unplug.** The link reports the failure to the Device page. Plug the board back in,
   rescan and connect again.

The protocol is deliberately small and versioned. One frame is:

```text
A5 5A | version u8 | seq u16 LE | len u16 LE | postcard payload | CRC-16/CCITT LE
```

The CRC covers `version`, `seq`, `len` and the payload. `crates/esp32-protocol` is
`no_std` and is compiled for both the host and the Xtensa target, so a message cannot
drift between the two ends.

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

- **Companion:** ESP32-S3 DevKitC-1 (or any board exposing the native USB peripheral),
  8 MB flash is the tested size. The BOOT button is GPIO0 (active low); the status LED
  is GPIO2. The DevKitC-1's onboard WS2812 is **not** driven: it needs a data protocol,
  and a plain GPIO is the portable choice. Wire an LED to GPIO2 (with a resistor) or
  change the two pin numbers in `firmware/esp32-s3/src/main.rs`.
- **Camera:** ESP32-S3-EYE — 8 MB flash, **8 MB octal PSRAM**, OV2640 on the DVP bus,
  LCD, ES8311 codec. The camera/SCCB/DVP pins are in [Camera and on-device
  AI](#camera-and-on-device-ai). The Rust protocol's `SetLed` targets the EYE's green LED
  (GPIO3), but the camera app disables the BSP LED helper, so treat `SetLed` as an
  Ack/host→device path test there; the companion's GPIO2 is the controllable LED.
- The USB cable goes to the **native USB** port, not the UART bridge. The board
  enumerates as `303a:1001`, `USB JTAG/serial debug unit`, usually `/dev/ttyACM0`
  and `COMx` on Windows. Its USB serial number is the MAC.
- The ESP32-S3's internal temperature sensor is not exposed by `esp-hal` 1.2.2, so the
  companion's telemetry reports `0` and the app shows `—`. The camera firmware reports
  `0` there too.

## Build and flash the companion firmware

The toolchain is Espressif's Xtensa Rust fork (1.97), installed by `espup`. It works on
aarch64 and x86_64 Linux; `/tmp` is often a small tmpfs, so keep the toolchain under
`$HOME`. The **camera** firmware has its own build in [Camera and Rust protocol
firmware](#camera-and-rust-protocol-firmware-integrated); this section is the companion.

```bash
# On the host, once:
#   espup install --targets esp32s3
#   install the prebuilt espflash binary
# Then:
firmware/esp32-s3/flash.sh                    # /dev/ttyACM0, native USB
ESP32_PORT=/dev/ttyUSB0 firmware/esp32-s3/flash.sh   # UART bridge, default reset
```

The same build runs in the family image, with the toolchain in a named volume:

```bash
scripts/linux/esp32/build-firmware.sh                 # build only
scripts/linux/esp32/build-firmware.sh --flash         # build + flash /dev/ttyACM0
scripts/linux/esp32/build-firmware.sh --flash --port /dev/ttyUSB0 --uart
```

The volume keeps `espup`, the Xtensa toolchain, `espflash`, the cargo registry and
`target/` between runs. Firmware sources stay on the host mount. The first run needs
network access; later runs are offline. The firmware's only path dependency is
`third_party/OxidANT/crates/esp32-protocol`, so **commit the OxidANT submodule before
moving this repository's gitlink**: a clean checkout whose gitlink predates that crate
cannot resolve the firmware build. The build runs as the image user; the flash step
runs as root because rootless nerdctl remaps `/dev/ttyACM0` to `nobody:nogroup`, which
the image user cannot open. Only `espflash` is root; the build artifacts stay owned by
the image user.

`firmware/esp32-s3/Cargo.lock` is committed: `--locked` is what makes the volume build
reproducible. The firmware is a separate crate with its own `rust-toolchain.toml`
(`channel = "esp"`); it is not a member of OxidANT's workspace and is not built by the
app's Cargokit path.

## App side

`kataglyphis_esp32` (OxidANT `crates/esp32`) owns discovery, framing and the two
threads:

- the **reader** parses frames, answers `Ping`, sends `HostHello` until the handshake
  and reports a 6 s silence as a disconnect;
- the **writer** owns the port and drains a channel, so the inference thread never
  blocks on USB.

It is a **desktop-only target dependency** of `oxidant`:

```toml
[target.'cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))'.dependencies]
kataglyphis_esp32 = { path = "crates/esp32" }
```

Android and wasm builds do not compile `serialport`; `esp32_available()` returns
`false` there. On Linux, `serialport` is built **without** its optional libudev
feature: port discovery uses its `/sys/class/tty` fallback, so no new native library
enters the packaged bundle and the riscv64 cross lane is unaffected.

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

The **Device** page (`lib/Pages/DevicePage/`) shows the port, firmware, MAC, uptime,
heap, temperature, button, the latest host-webcam detection count, the LED sliders and a
ping. When the board's camera firmware is connected, it also shows **On-device camera**
(count and best score) once the first `camera` event arrives.

`Esp32Event.kind == "camera"` carries the board's own detector: `value` is the hit
count, `scorePermille` the best score (0–1000). The companion never sends it, so the
field stays hidden there. It is a view over `Esp32Controller`; `Esp32Api` is the seam
the tests fake, so no Rust library is needed in `flutter test`.

### Detections without Dart

`webcam_engine`'s `EngineConfig` gained `on_detections`. `api/webcam.rs` installs
`api::esp32::notify_detections`, so every inference result is offered to the link on
the inference thread. `Link::notify_detection` throttles: a change at most every
100 ms, a steady count every 250 ms, zero every second. The firmware pulses GPIO2 for
120–300 ms depending on the score. No Dart code runs for this path.

`esp32NotifyDetection` exists for sources that live outside the Rust webcam engine,
such as the ObservANT web page.

The camera firmware reports the opposite direction: its ESP-DL detector calls
`omni_proto_on_detections`, and the Rust task sends `CameraDetection` to the host. The
Device page renders the count and best score; it does **not** draw the boxes (the
ESP-WHO LCD app can, but the integrated firmware uses the terminal variant and the
message carries count/score only). The host webcam path above is unchanged.

## Camera and on-device AI

**Status 2026-10-18: the integrated camera firmware is built and flashed.** Variant A
(true on-device AI) runs on the ESP32-S3-EYE; the companion (`firmware/esp32-s3`) remains
the fallback. The camera firmware is a separate ESP-IDF project because it needs
`esp32-camera`/ESP-DL; the Rust protocol is a staticlib inside it.

### Probe result

`firmware/esp32-s3-probe` replaces the companion for one boot, reports PSRAM and scans
the camera's SCCB bus. Results on this board:

| Item | Result |
| --- | --- |
| Board | **ESP32-S3-EYE** (8 MB flash, **8 MB octal PSRAM**) |
| Camera | **OV2640**, SCCB address `0x30`, PID `0x26`, VER `0x42` |
| SCCB | SDA GPIO4, SCL GPIO5 (the ES8311 codec also answers at `0x12` on this bus) |
| XCLK | GPIO15; the sensor answered only after a clean **10 MHz** LEDC clock |
| DVP | VSYNC 6, HREF 7, PCLK 13, Y2…Y9 = 11, 9, 8, 10, 12, 18, 17, 16 |

The first scan without XCLK found only the codec; a busy-loop clock also missed the
sensor, while the LEDC's 10 MHz made it answer. That is why the probe starts the clock
before scanning. The probe is a one-boot diagnostic; the integrated camera firmware was
flashed after it.

### Camera and Rust protocol firmware (integrated)

The script now builds the **integrated firmware**: Espressif's ESP-WHO `object_detect`
example with the `cat_detect` model (C++ camera + ESP-DL) **plus**
`firmware/esp32-s3-eye/rust_protocol`, a `no_std` staticlib that owns the native USB
Serial/JTAG protocol. The C++ detection callback calls `omni_proto_on_detections`; the
Rust task sends `Hello`, `Telemetry` and `CameraDetection`, and handles `HostHello`,
`Ping`, `SetLed` and `SetTelemetryPeriod`. The C++ app console is UART0, so the USB port
belongs to the protocol — **`idf.py monitor` is not the view**; use the host probe or
the app's Device page.

```bash
scripts/linux/esp32/build-eye-demo.sh            # build only
scripts/linux/esp32/build-eye-demo.sh --flash    # build and flash /dev/ttyACM0
```

The script clones ESP-WHO into `~/.cache/esp-who`, patches the example to the terminal
app and the esp-dl 3.3.13 API, builds the Rust staticlib on the host (espup's `esp`
toolchain), copies it into the ESP-IDF project, and builds in the official
`espressif/idf:release-v5.5` image. That image is separate from the family `:latest`
image, which carries no ESP-IDF. The first build downloads the component-managed BSP,
ESP-DL and the cat model.

The model is `espressif/cat_detect` (the packed model is `espdet_pico_224_224_cat`,
498 KB); the BSP is `esp32_s3_eye_noglib` with OV2640 DVP RGB565 at 240×240, 8 MB flash
and octal PSRAM. The factory app partition is 8000K.

**Verified 2026-10-18** after building and flashing the integrated script: the boot log
reports `Found 8MB PSRAM device`, `Camera PID=0x26 VER=0x42`, `Detected OV2640 camera`,
five PSRAM frame buffers and the cat model loaded. The app binary is 0x2873d0 bytes
(2.64 MB), leaving 68 % of the 8000K partition free. The host probe sees:

```
hello: DeviceInfo { protocol: 1, firmware 0.2.0, chip Esp32S3, mac [E8:06:90:9D:3E:78] }
telemetry: Telemetry { uptime_ms: 1025, free_heap: 4967415, ... }
camera: 0 hit(s), best 0 per mille
ack: command 3        # SetLed
pong: 42
```

`firmware_patch` carries the USB Serial/JTAG driver install result (`0` = success). The
`camera` events are the on-device detector; they read 0 until a cat is in view.

The script pins **ESP-WHO `b6ac2be`**, **BSP 5.0.2** and **cat_detect 0.3.0**. Master's
example code uses the BSP 6.0.0 `bsp_camera_cfg_t` API while its lock and sdkconfig
defaults are still 5.0.2; pinning the commit before the BSP 6.0.0/`esp_video` migration
avoids that mismatch. The newer esp-dl also needs its `RGB565BE` enum, `img.bytes()`,
two-argument `sw_decode_jpeg` and non-`caps` `cvt_pix` call sites patched; the script
does that. The Rust archive sits at the end of the IDF link line, so the main component
forces `esp_efuse_mac_get_default`, `xTaskCreatePinnedToCore` and
`usb_serial_jtag_driver_install` with `-Wl,--undefined`.

### What A means here

- **On the board:** ESP-IDF + the `esp32-camera` driver + ESP-DL/ESP-WHO (C/C++),
  because the optimised camera and inference code is C/C++. Rust owns the USB protocol,
  control and telemetry as a `staticlib` linked into that app — as much Rust as the
  vendor components allow.
- **On the host:** `kataglyphis_esp32` has the `CameraDetection` link event; the Device
  page shows the on-device count and best score. A JPEG preview is the next optional
  step.
- **Model:** the ESP-DL `espdet_pico_224_224_cat` detector. The ESP32-S3-EYE's 8 MB
  flash is tight; a 320×320 YOLO11n model plus ESP-IDF and the Rust app does not fit
  comfortably. A 16 MB flash board would allow a larger model.
- **Expectation:** a few frames per second, not 30 fps video. Good for "a cat arrived"
  events, not for replacing the host's ONNX model.

### Seeing it

```bash
# Host probe (same events the app receives):
cd third_party/OxidANT
cargo run -p kataglyphis_esp32 --example probe

# Or rebuild the desktop app and open the Device page, then Connect.
flutter run -d linux
```

Point the camera at a cat; the probe's `camera:` line and the Device page's
**On-device camera** field change together. Without a cat they stay at 0.

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

The probe lists the ports, opens the first Espressif board, prints `hello`,
`telemetry`, `camera`, `ack` and `pong`, pulses the LED and sends one detection. A
healthy run against the camera firmware looks like:

```
hello: DeviceInfo { protocol: 1, firmware_major: 0, firmware_minor: 2,
                    firmware_patch: 0, chip: Esp32S3, mac: [...] }
telemetry: Telemetry { uptime_ms: 1025, free_heap: 4967415, ... }
camera: 0 hit(s), best 0 per mille
ack: command 3        # SetLed
pong: 42
```

`firmware_patch` is the camera firmware's USB Serial/JTAG driver install result (`0` =
success). The `camera` line is the on-device detector; it stays at 0 until a cat is in
view. Against the companion the line is absent and `firmware_minor` is 1.

## Troubleshooting

- **`Permission denied` on `/dev/ttyACM0`**: on the host, add your user to the device's
  group (usually `plugdev`/`dialout`). The container script runs only the flash step as
  root because rootless nerdctl remaps the device node to `nobody:nogroup`.
- **`espflash` cannot connect on `/dev/ttyACM0`**: the native USB port needs
  `--before usb-reset`; a UART bridge (`/dev/ttyUSB0`) needs `default-reset`. The
  scripts select it from the port name, or pass `--uart`.
- **The board reboots when the port opens**: avoid toggling DTR/RTS on the native USB
  port; the probe does not.
- **The app shows "desktop builds only"**: that is the web/Android build. On Linux or
  Windows, check that the app was rebuilt with the new Rust core and that the port is
  visible in the dropdown.
- **The device is silent after flashing**: check the baud-independent USB CDC link
  with `espflash board-info`; then run the probe. The companion sends `Hello` every
  500 ms until it sees `HostHello`; the camera firmware every 2 s. The host may be the
  silent side.
- **The camera is not found**: use `firmware/esp32-s3-probe`; the OV2640's SCCB only
  answers with **XCLK 10 MHz on GPIO15**. Check the camera ribbon and the SCCB pair
  (SDA4/SCL5); a bare I2C scan without XCLK finds only the ES8311 codec at `0x12`.
- **`camera:` stays at 0**: the on-device model only reports a cat it is sure about;
  check the lighting and point the camera at the cat. The events are throttled to one
  per 100 ms, not one per camera frame.
- **The app connects but has no "On-device camera" field**: the board is running the
  **companion**, which sends no `CameraDetection`. Flash the camera firmware with
  `scripts/linux/esp32/build-eye-demo.sh --flash`; the companion is restored with
  `firmware/esp32-s3/flash.sh`.
- **No `Hello` / the app stays disconnected**: the camera firmware's C++ console must
  be **UART0** (`CONFIG_ESP_CONSOLE_UART_DEFAULT`); a USB console consumes the host's
  `HostHello` before the Rust read. `firmware_patch` in `Hello` is the USB driver
  install result (`0` = success). `idf.py monitor` is not the view; it competes for the
  protocol port.
- **The ESP-WHO build fails**: use the script, which pins ESP-WHO `b6ac2be`, BSP
  `5.0.2`, `cat_detect` `0.3.0` and patches the esp-dl 3.3.13 API and the prebuilt
  library's `-Wl,--undefined` symbols. Bumping the pin needs the code, defaults and
  patches moved together; the first build downloads the BSP and model.
- **Toolchain install fails with "No space left on device"**: `espup` was pointed at
  `/tmp` (a 4 GB tmpfs on the Pi). Use `$HOME/.cache/kataglyphis-esp`.
