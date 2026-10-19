#!/usr/bin/env bash
# Builds (and optionally flashes) the ESP32-S3 companion inside the family image.
#
# The first run bootstraps espup's Xtensa toolchain and espflash into a named volume,
# so later runs are offline and warm. Firmware sources stay on the host mount; only
# the toolchain, cargo registry and target tree live on the volume.
#
#   scripts/linux/esp32/build-firmware.sh
#   scripts/linux/esp32/build-firmware.sh --flash
#   scripts/linux/esp32/build-firmware.sh --flash --port /dev/ttyUSB0 --uart
#
# Env: KATAGLYPHIS_IMAGE, KATAGLYPHIS_ENGINE, KATAGLYPHIS_ESP32_VOLUME.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# The image ref comes only from the hub; two assignments, since set -e misses a substitution failing mid-expansion.
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "${repo_root}/scripts/linux/lib/antfrastructure.sh"
_ci_image_ref_sh="$(antfrastructure_path linux/scripts/ci-image-ref.sh)"
image="${KATAGLYPHIS_IMAGE:-$(bash "${_ci_image_ref_sh}")}"
engine="${KATAGLYPHIS_ENGINE:-nerdctl}"
volume="${KATAGLYPHIS_ESP32_VOLUME:-oa-esp32-toolchain}"
port="${ESP32_PORT:-/dev/ttyACM0}"
flash=0
uart=0

usage() {
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --flash) flash=1; shift ;;
        --port) port="${2:?--port needs a device}"; shift 2 ;;
        --uart) uart=1; shift ;;
        --image) image="${2:?--image needs a tag}"; shift 2 ;;
        --engine) engine="${2:?--engine needs a binary}"; shift 2 ;;
        --volume) volume="${2:?--volume needs a name}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

command -v "$engine" >/dev/null 2>&1 || {
    echo "container engine not found: $engine" >&2
    exit 2
}
if [[ "$flash" == 1 && ! -c "$port" ]]; then
    echo "flash requested but $port is not a character device" >&2
    exit 2
fi

# The lane's rule: a volume mounted into the image belongs to its user, not root.
"$engine" volume create "$volume" >/dev/null 2>&1 || true
"$engine" run --rm --pull=missing --user root --entrypoint chown \
    --mount "type=volume,source=$volume,target=/vol" \
    "$image" -R 1001:1001 /vol >/dev/null 2>&1 || true

run_args=(
    run --rm --pull=missing
    --user 1001:1001
    -v "$repo_root:/workspace"
    -w /workspace/firmware/esp32-s3
    --mount "type=volume,source=$volume,target=/opt/esp32"
    -e HOME=/home/kataglyphis
    -e RUSTUP_HOME=/opt/esp32/rustup
    -e CARGO_HOME=/opt/esp32/cargo
    -e CARGO_TARGET_DIR=/opt/esp32/target
    -e PATH=/opt/esp32/cargo/bin:/opt/esp32/bin:/usr/local/cargo/bin:/usr/local/bin:/usr/bin:/bin
)

before="usb-reset"
[[ "$uart" == 1 ]] && before="default-reset"

"$engine" "${run_args[@]}" "$image" bash -lc "
set -euo pipefail
mkdir -p /opt/esp32/bin /opt/esp32/cargo /opt/esp32/rustup

if [ ! -x /opt/esp32/bin/espup ]; then
  case \"\$(uname -m)\" in
    aarch64) host=aarch64-unknown-linux-gnu ;;
    x86_64)  host=x86_64-unknown-linux-gnu ;;
    *) echo \"unsupported container architecture: \$(uname -m)\" >&2; exit 2 ;;
  esac
  curl -fL \"https://github.com/esp-rs/espup/releases/latest/download/espup-\${host}\" \
    -o /opt/esp32/bin/espup
  chmod +x /opt/esp32/bin/espup
fi

if [ ! -d /opt/esp32/rustup/toolchains/esp ]; then
  /opt/esp32/bin/espup install --targets esp32s3 \
    --export-file /opt/esp32/export.sh --disable-timeouts
fi

if [ ! -x /opt/esp32/bin/espflash ]; then
  case \"\$(uname -m)\" in
    aarch64) host=aarch64-unknown-linux-gnu ;;
    x86_64)  host=x86_64-unknown-linux-gnu ;;
  esac
  curl -fL \"https://github.com/esp-rs/espflash/releases/download/v4.6.0/espflash-\${host}.zip\" \
    -o /tmp/espflash.zip
  python3 -m zipfile -e /tmp/espflash.zip /opt/esp32/bin/
  chmod +x /opt/esp32/bin/espflash
fi

source /opt/esp32/export.sh
cargo +esp build --release --locked
"

# Rootless nerdctl maps the device node to nobody:nogroup, so only the flash step runs as root.
if [[ "$flash" == 1 ]]; then
    "$engine" run --rm --pull=never --user root --device "$port" \
        --mount "type=volume,source=$volume,target=/opt/esp32" \
        "$image" /opt/esp32/bin/espflash flash --chip esp32s3 --port "$port" \
        --before "$before" --non-interactive \
        /opt/esp32/target/xtensa-esp32s3-none-elf/release/omni-esp32s3
fi
