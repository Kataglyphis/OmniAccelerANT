#!/usr/bin/env bash
# Builds and flashes the companion with the host's espup toolchain (ESPUP_HOME, default ~/.cache/kataglyphis-esp).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

espup_home="${ESPUP_HOME:-${HOME}/.cache/kataglyphis-esp}"
if [[ -f "${espup_home}/export.sh" ]]; then
    # shellcheck disable=SC1091
    source "${espup_home}/export.sh"
    export RUSTUP_HOME="${espup_home}/rustup"
    export CARGO_HOME="${espup_home}/cargo"
    export PATH="${espup_home}/cargo/bin:${espup_home}/bin:${PATH}"
elif [[ -f "${HOME}/export-esp.sh" ]]; then
    # shellcheck disable=SC1091
    source "${HOME}/export-esp.sh"
else
    echo "no espup export file found; run 'espup install --targets esp32s3' first" >&2
    exit 2
fi

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
