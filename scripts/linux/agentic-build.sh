#!/usr/bin/env bash
set -euo pipefail

# Agentic-loop build adapter (Linux): maps the loop's
# `--preset <name> --build-dir <dir>` contract onto this repo's native Linux
# lane, scripts/linux/run-native-linux.sh. The loop's bash library hard-codes
# that argument shape (third_party/ANTfrastructure/linux/scripts/lib/agentic-loop.sh).
#
# NOT yet exercised end-to-end: the loop has only been run on Windows so far,
# and running it on Linux additionally needs the opencode CLI on that host.
# The lane's own gates run inside this call; packaging stays off because a loop
# build only needs build success. --build-dir is accepted for contract parity
# and ignored - the lane owns its build directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PRESET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --preset) PRESET="${2:-}"; shift 2 ;;
    --build-dir) shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

case "$PRESET" in
  *debug*) BUILD_MODE="debug" ;;
  *profile*) BUILD_MODE="profile" ;;
  *) BUILD_MODE="release" ;;
esac

exec bash "${REPO_ROOT}/scripts/linux/run-native-linux.sh" \
  --build-mode "$BUILD_MODE" --no-package --run-docs false
