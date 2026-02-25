#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/cli-common.sh"
source "$SCRIPT_DIR/lib/packaging-common.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/linux/run-android.sh [options]

Options:
  -a, --arch <x64|arm64>        Host architecture label for artifact naming (default: auto-detect)
      --build-mode <debug|profile|release> Build mode for flutter build apk (default: release)
  -n, --app-name <name>         Artifact base name (default: kataglyphis-inference-engine-apk)
      --flutter-dir <path>      Optional Flutter SDK directory (uses <path>/bin/flutter)
  -h, --help                    Show this help

Notes:
  - This runs on the host (no Docker).
  - Requires flutter + dart available (either on PATH or via --flutter-dir).
EOF
}

APP_NAME="kataglyphis-inference-engine-apk"
MATRIX_ARCH="$(detect_arch)"
BUILD_MODE="release"
FLUTTER_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--arch)
      MATRIX_ARCH="${2:-}"
      shift 2
      ;;
    --build-mode)
      BUILD_MODE="${2:-}"
      shift 2
      ;;
    -n|--app-name)
      APP_NAME="${2:-}"
      shift 2
      ;;
    --flutter-dir)
      FLUTTER_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$APP_NAME" ]]; then
  echo "Error: --app-name must not be empty" >&2
  exit 2
fi

if ! validate_arch "$MATRIX_ARCH"; then
  exit 2
fi

case "$BUILD_MODE" in
  debug|profile|release) ;;
  *)
    echo "Error: --build-mode must be one of: debug, profile, release (got: ${BUILD_MODE:-<empty>})" >&2
    exit 2
    ;;
esac

ensure_flutter_bin_on_path "$FLUTTER_DIR"

cd "$REPO_ROOT"

require_cmd flutter
require_cmd dart

flutter pub get
run_nonfatal dart format --output=none --set-exit-if-changed .
run_nonfatal dart analyze
run_nonfatal flutter test

flutter config --enable-android

flutter clean
flutter pub get
flutter build apk --"$BUILD_MODE"

if [[ "$BUILD_MODE" == "release" ]]; then
  package_android_apk_outputs_tar "$MATRIX_ARCH" "$APP_NAME"
else
  echo "Info: packaging skipped because --build-mode is '$BUILD_MODE' (packaging is release-only)."
fi
