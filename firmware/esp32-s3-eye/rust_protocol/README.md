# `omni_esp32_eye_proto`

The Rust half of the ESP32-S3-EYE camera firmware: a `no_std` `staticlib` linked into the
ESP-WHO/ESP-IDF C++ app. The C++ detection callback calls `omni_proto_on_detections`; a FreeRTOS
task owns the native USB Serial/JTAG link, with the framed protocol from
`third_party/OxidANT/crates/esp32-protocol`.

## C ABI

`include/omni_proto.h`:

```c
void omni_proto_start(void);
void omni_proto_on_detections(unsigned count, unsigned score_permille);
```

`omni_proto_start` creates the protocol task (12 KiB stack, priority 5, `tskNO_AFFINITY`). The
task installs the USB Serial/JTAG driver, reads host frames, answers `HostHello` with
`Hello`/`Telemetry`, handles `Ping`, `SetLed` and `SetTelemetryPeriod`, and sends
`CameraDetection` when the detector calls the second function. `Hello` repeats every 2 s;
`firmware_patch` carries the USB driver install result (`0` = success). `SetLed` targets the
EYE's green LED on GPIO3, but the camera app disables the BSP LED helper: the Ack is the
reliable part, not the light.

## Build

```bash
source ~/.cache/kataglyphis-esp/export.sh   # or ~/export-esp.sh
export RUSTUP_HOME=~/.cache/kataglyphis-esp/rustup
export CARGO_HOME=~/.cache/kataglyphis-esp/cargo
cargo +esp build --release
```

`.cargo/config.toml` selects `xtensa-esp32s3-none-elf` and builds `core` from `rust-src`. The
archive is `target/xtensa-esp32s3-none-elf/release/libomni_esp32_eye_proto.a` (about 800 KiB).

`scripts/linux/esp32/build-eye-demo.sh` builds this crate, copies the archive and
`include/omni_proto.h` into the ESP-WHO clone, patches the C++ callback and `app_main.cpp`, and
links the archive into the ESP-IDF app. The archive sits at the end of the IDF link line, so
`main/CMakeLists.txt` adds `-Wl,--undefined=esp_efuse_mac_get_default`,
`-Wl,--undefined=xTaskCreatePinnedToCore` and `-Wl,--undefined=usb_serial_jtag_driver_install`.

## Rules

- The C++ app console must be **UART0**: a USB console consumes the host's `HostHello` before
  this task reads it.
- `idf.py monitor` is not the view; it competes for the protocol port. Use
  `cargo run -p kataglyphis_esp32 --example probe` or the app's Device page.
- The ESP-WHO pin and the esp-dl API patches live in `scripts/linux/esp32/build-eye-demo.sh`;
  see `docs/source/esp32.md` § *Camera and on-device AI*.
