#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "x64" ;;
  esac
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not found: $cmd" >&2
    return 1
  fi
}

run_nonfatal() {
  if ! "$@"; then
    echo "Warning: command failed (ignored): $*" >&2
    return 0
  fi
}

usage() {
  cat <<'EOF'
Usage:
  bash scripts/linux/run-native-linux.sh [options]

Options:
  -a, --arch <x64|arm64>        Target architecture (default: auto-detect)
  -n, --app-name <name>         Artifact base name (default: kataglyphis-inference-engine)
      --flutter-dir <path>      Optional Flutter SDK directory (uses <path>/bin/flutter)
  -h, --help                    Show this help

Notes:
  - This runs on the host (no Docker).
  - Requires flutter + dart available (either on PATH or via --flutter-dir).
EOF
}

APP_NAME="kataglyphis-inference-engine"
MATRIX_ARCH="$(detect_arch)"
FLUTTER_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--arch)
      MATRIX_ARCH="${2:-}"
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

case "$MATRIX_ARCH" in
  x64|arm64) ;;
  *)
    echo "Error: --arch must be x64 or arm64 (got: $MATRIX_ARCH)" >&2
    exit 2
    ;;
esac

if [[ -n "$FLUTTER_DIR" && -x "${FLUTTER_DIR}/bin/flutter" ]]; then
  export PATH="${FLUTTER_DIR}/bin:$PATH"
fi

cd "$REPO_ROOT"

require_cmd flutter
require_cmd dart

flutter pub get
run_nonfatal dart format --output=none --set-exit-if-changed .
run_nonfatal dart analyze
run_nonfatal flutter test

flutter config --enable-linux-desktop

flutter clean
flutter pub get
flutter build linux --release

rm -rf "build/linux/${MATRIX_ARCH}/release/obj" || true
rm -rf ~/.pub-cache/hosted || true
mkdir -p out

if [[ ! -d "build/linux/${MATRIX_ARCH}/release/bundle" ]]; then
  echo "Error: expected bundle directory not found: build/linux/${MATRIX_ARCH}/release/bundle" >&2
  exit 1
fi

rm -rf "out/${APP_NAME}-bundle" || true
cp -r "build/linux/${MATRIX_ARCH}/release/bundle" "out/${APP_NAME}-bundle"
tar -C out -czf "${APP_NAME}-linux-${MATRIX_ARCH}.tar.gz" "${APP_NAME}-bundle"
