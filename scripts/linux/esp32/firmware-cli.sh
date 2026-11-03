#!/usr/bin/env bash
# What both ESP32 builders accept and check before any container work; the build recipes stay in the callers.
# shellcheck source=scripts/linux/lib/entry-options.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/entry-options.sh"

# An unknown argument always prints that builder's own usage.
esp32_refuse_argument() {
  echo "unknown argument: $1" >&2
  usage >&2
  exit 2
}

# esp32_check_host <engine> <flash> <port>: fails before a clone or a pull when this host cannot finish the request.
esp32_check_host() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "container engine not found: $1" >&2
    exit 2
  }
  if [[ "$2" == 1 && ! -c "$3" ]]; then
    echo "flash requested but $3 is not a character device" >&2
    exit 2
  fi
}
