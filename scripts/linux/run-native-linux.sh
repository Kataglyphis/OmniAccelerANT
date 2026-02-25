#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/cli-common.sh"
source "$SCRIPT_DIR/lib/container-steps.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/linux/run-native-linux.sh [options]

Options:
  -a, --arch <x64|arm64>        Target architecture (default: auto-detect)
  --build-mode <debug|profile|release> Build mode for flutter build linux (default: release)
  -n, --app-name <name>         Artifact base name (default: kataglyphis-inference-engine)
      --package-formats <csv>   Packaging formats (default: tar,appimage,flatpak,deb)
      --no-package              Build only (skip packaging)
      --strict-checks <bool>    Fail on format/analyze/test errors (default: true in CI, false locally)
      --run-docs <bool>         Generate docs (default: true, only on x64)
      --flutter-dir <path>      Optional Flutter SDK directory (uses <path>/bin/flutter)
  -h, --help                    Show this help

Notes:
  - This runs on the host (no Docker).
  - Requires flutter + dart available (either on PATH or via --flutter-dir).
EOF
}

APP_NAME="kataglyphis-inference-engine"
MATRIX_ARCH="$(detect_arch)"
BUILD_MODE="release"
FLUTTER_DIR=""
PACKAGE_FORMATS="tar,appimage,flatpak,deb"
RUN_PACKAGING=1
RUN_DOCS="1"
STRICT_CHECKS=""

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
    --package-formats)
      PACKAGE_FORMATS="${2:-}"
      shift 2
      ;;
    --no-package)
      RUN_PACKAGING=0
      shift
      ;;
    --strict-checks)
      STRICT_CHECKS="${2:-}"
      shift 2
      ;;
    --run-docs)
      RUN_DOCS="${2:-}"
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

STRICT_CHECKS="$(resolve_strict_checks "$STRICT_CHECKS")"

ensure_flutter_bin_on_path "$FLUTTER_DIR"

cd "$REPO_ROOT"

require_cmd flutter
require_cmd dart

flutter pub get
run_check_cmd "$STRICT_CHECKS" dart format --output=none --set-exit-if-changed .
run_check_cmd "$STRICT_CHECKS" dart analyze
run_check_cmd "$STRICT_CHECKS" flutter test

flutter config --enable-linux-desktop

flutter clean
flutter pub get
flutter build linux --"$BUILD_MODE"

if [[ "$RUN_PACKAGING" -eq 1 && "$BUILD_MODE" == "release" ]]; then
  _strict_package_arg=()
  if maybe_truthy "$STRICT_CHECKS"; then
    _strict_package_arg+=(--strict)
  fi
  bash scripts/linux/lib/package-linux.sh --arch "$MATRIX_ARCH" --app-name "$APP_NAME" --formats "$PACKAGE_FORMATS" "${_strict_package_arg[@]}"
elif [[ "$RUN_PACKAGING" -eq 1 ]]; then
  echo "Info: packaging skipped because --build-mode is '$BUILD_MODE' (packaging is release-only)."
else
  echo "Info: packaging skipped (--no-package)."
fi

# Docs
case "${RUN_DOCS,,}" in
  1|true|yes|y|on)
    if [[ "$MATRIX_ARCH" == "x64" ]]; then
      bash scripts/linux/lib/generate-docs.sh
    else
      echo "Info: docs generation is only enabled on x64; skipping for arch '$MATRIX_ARCH'."
    fi
    ;;
esac
