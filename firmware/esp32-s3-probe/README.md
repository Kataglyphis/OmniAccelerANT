# `omni-esp32s3-probe`

A one-boot hardware diagnostic for the ESP32-S3-EYE camera route. It replaces the
companion for one boot, reports PSRAM, starts the camera's XCLK and scans the two common
SCCB pin pairs for an OV2640/OV5640.

## Build and flash

```bash
source ~/.cache/kataglyphis-esp/export.sh   # or ~/export-esp.sh
export RUSTUP_HOME=~/.cache/kataglyphis-esp/rustup
export CARGO_HOME=~/.cache/kataglyphis-esp/cargo
cargo +esp build --release
espflash flash --monitor --chip esp32s3 --port /dev/ttyACM0 --before usb-reset \
  target/xtensa-esp32s3-none-elf/release/omni-esp32s3-probe
```

## What it reports

- `PSRAM: <bytes>` from `esp-hal`'s auto-detected octal/quad PSRAM. The tested EYE has
  8 MiB.
- An I2C scan of **SDA4/SCL5** with **XCLK 10 MHz on GPIO15** (LEDC) and, if no camera
  answered, **SDA40/SCL39** for the XIAO ESP32S3 Sense.
- For an OV sensor: `PID`/`VER` (OV2640 `0x26`/`0x42`, OV5640 `0x56`/`0x40`).
- `alive; PSRAM <bytes>` every 5 s so a late monitor still sees output.

The OV2640's SCCB slave only answers with XCLK running; a scan without it finds only the
ES8311 codec at `0x12`. The companion is restored with `firmware/esp32-s3/flash.sh`.
Full context: `docs/source/esp32.md` § *Camera and on-device AI*.
