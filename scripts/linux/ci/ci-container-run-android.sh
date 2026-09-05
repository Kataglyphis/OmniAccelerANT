#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/container-steps.sh"
source "$SCRIPT_DIR/../lib/cli-common.sh"
source "$SCRIPT_DIR/../lib/packaging-common.sh"
source "$SCRIPT_DIR/../codeql/codeql-common.sh"
source "$SCRIPT_DIR/../codeql/codeql-android.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/linux/ci/ci-container-run-android.sh [options]

Options:
  -a, --arch <x64|arm64>        Target architecture label (required)
  --build-mode <debug|profile|release> Build mode for flutter build apk (default: release)
      --flutter-dir <path>      Flutter SDK directory (default: /opt/flutter, baked into the image)
  -n, --app-name <name>         Artifact base name (required)
      --run-codeql <bool>       Run CodeQL scan (default: true)
  -h, --help                    Show this help
EOF
}

MATRIX_ARCH=""
BUILD_MODE="release"
FLUTTER_DIR="/opt/flutter"
APP_NAME=""
RUN_CODEQL="1"
STRICT_CHECKS="0"

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
    --flutter-dir)
      FLUTTER_DIR="${2:-}"
      shift 2
      ;;
    -n|--app-name)
      APP_NAME="${2:-}"
      shift 2
      ;;
    --run-codeql)
      RUN_CODEQL="${2:-}"
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

if ! validate_arch "$MATRIX_ARCH"; then
  usage >&2
  exit 2
fi

case "$BUILD_MODE" in
  debug|profile|release) ;;
  *)
    echo "Error: --build-mode must be one of: debug, profile, release (got: ${BUILD_MODE:-<empty>})" >&2
    usage >&2
    exit 2
    ;;
esac


if ! validate_non_empty "--app-name" "$APP_NAME"; then
  usage >&2
  exit 2
fi

# Non-strict, matching the workflow.
STRICT_CHECKS="0"

build_android_apk_release() {
  local build_mode="${1:-release}"
  flutter clean
  flutter pub get
  flutter build apk --"$build_mode"
}

REPO_ROOT="$(resolve_repo_root /workspace)"
cd "$REPO_ROOT"

git_safe_dirs "$FLUTTER_DIR"

assert_flutter_available "$FLUTTER_DIR" || exit 2
source_bashrc_and_add_flutter_to_path "$FLUTTER_DIR"
run_flutter_common_checks "$STRICT_CHECKS"
run_check_cmd "$STRICT_CHECKS" flutter config --enable-android
setup_compiler_cache
export_android_gstreamer_env
export_toolchain_env "$MATRIX_ARCH"

if maybe_truthy "$RUN_CODEQL"; then
  if ! run_codeql_android "$FLUTTER_DIR" "$BUILD_MODE"; then
    echo "Warning: CodeQL failed; continuing with regular APK build." >&2
    cd /workspace
    build_android_apk_release "$BUILD_MODE"
  fi
else
  build_android_apk_release "$BUILD_MODE"
fi

if [[ "$BUILD_MODE" == "release" ]]; then
  package_android_apk_outputs_tar "$MATRIX_ARCH" "$APP_NAME"
else
  echo "Info: packaging skipped because --build-mode is '$BUILD_MODE' (packaging is release-only)."
fi
