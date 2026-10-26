#!/usr/bin/env bash
# Builds and flashes the companion with the host's espup toolchain (ESPUP_HOME, default ~/.cache/kataglyphis-esp).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

repo_root="$(cd "${here}/../.." && pwd)"
# shellcheck source=scripts/linux/lib/espup-env.sh
source "${repo_root}/scripts/linux/lib/espup-env.sh"
omni_espup_environment

command -v espflash >/dev/null 2>&1 || {
    echo "espflash is not on PATH; install it from https://github.com/esp-rs/espflash/releases" >&2
    exit 2
}

cargo +esp build --release --locked

port="${ESP32_PORT:-/dev/ttyACM0}"
before="usb-reset"
[[ "$port" == /dev/ttyUSB* ]] && before="default-reset"
exec espflash flash --chip esp32s3 --port "$port" --before "$before" --non-interactive \
    target/xtensa-esp32s3-none-elf/release/omni-esp32s3
