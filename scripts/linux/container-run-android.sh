#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/container-steps.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/linux/container-run-android.sh [options]

Options:
  -a, --arch <x64|arm64>        Target architecture label (required)
      --flutter-version <ver>   Flutter version (required)
      --flutter-dir <path>      Flutter SDK installation directory (default: /workspace/flutter)
  -n, --app-name <name>         Artifact base name (required)
      --run-codeql <bool>       Run CodeQL scan (default: true)
  -h, --help                    Show this help
EOF
}

MATRIX_ARCH=""
FLUTTER_VERSION=""
FLUTTER_DIR="/workspace/flutter"
APP_NAME=""
RUN_CODEQL="1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--arch)
      MATRIX_ARCH="${2:-}"
      shift 2
      ;;
    --flutter-version)
      FLUTTER_VERSION="${2:-}"
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

case "$MATRIX_ARCH" in
  x64|arm64) ;;
  *)
    echo "Error: --arch must be x64 or arm64" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ -z "$FLUTTER_VERSION" ]]; then
  echo "Error: --flutter-version is required" >&2
  usage >&2
  exit 2
fi

if [[ -z "$APP_NAME" ]]; then
  echo "Error: --app-name is required" >&2
  usage >&2
  exit 2
fi

export MATRIX_ARCH
export FLUTTER_VERSION
export FLUTTER_DIR
export APP_NAME

REPO_ROOT="/workspace"
cd "$REPO_ROOT"

git_safe_dirs

if [[ "${MATRIX_ARCH}" == "arm64" ]]; then
  echo "Warning: Android build flow currently uses x86-64 Flutter bootstrap script; MATRIX_ARCH=${MATRIX_ARCH}" >&2
fi

MATRIX_ARCH=x64 setup_flutter_sdk
source_bashrc_and_add_flutter_to_path
run_flutter_common_checks
flutter config --enable-android
export_toolchain_env

if maybe_truthy "$RUN_CODEQL"; then
  codeql_install_cli
  cd /workspace
  codeql_download_packs codeql/cpp-queries codeql/rust-queries codeql/java-queries
  codeql_write_build_script /tmp/codeql-build.sh "flutter build apk --release"
  codeql_create_db_cluster /tmp/codeql-build.sh --language=cpp --language=c --language=rust --language=java --language=kotlin
  codeql_analyze_cpp
  codeql_analyze_kotlin
  codeql_analyze_rust
else
  flutter clean
  flutter pub get
  flutter build apk --release
fi

package_android_apk_outputs_tar
