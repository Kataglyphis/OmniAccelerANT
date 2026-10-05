#!/usr/bin/env bash
set -euo pipefail

# Maps the agentic loop's hard-coded `--preset --build-dir` onto lane-native-linux.sh; the lane owns its build dir.

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

exec bash "${REPO_ROOT}/scripts/linux/ci/lane-native-linux.sh" \
  --build-mode "$BUILD_MODE" --no-package --run-docs false
