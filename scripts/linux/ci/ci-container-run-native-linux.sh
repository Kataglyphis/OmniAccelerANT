#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/container-steps.sh"
source "$SCRIPT_DIR/../lib/cli-common.sh"
source "$SCRIPT_DIR/../lib/packaging-common.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/linux/ci/ci-container-run-native-linux.sh [options]

Options:
  -a, --arch <x64|arm64>        Target architecture (required)
  --build-mode <debug|profile|release> Build mode for flutter build linux (default: release)
      --flutter-dir <path>      Flutter SDK directory (default: /opt/flutter, baked into the image)
  -n, --app-name <name>         Artifact base name (required)
      --package-formats <csv>   Packaging formats (default: tar)
      --install-packaging-deps <bool> Install deps for deb/flatpak/appimage (default: false)
      --strict-checks <bool>    Fail on format/analyze/test errors (default: true in CI, false locally)
      --run-codeql <bool>       Run CodeQL scan (default: false)
      --run-docs <bool>         Generate docs (default: true)
  -h, --help                    Show this help
EOF
}

MATRIX_ARCH=""
BUILD_MODE="release"
FLUTTER_DIR="/opt/flutter"
APP_NAME=""
PACKAGE_FORMATS="tar"
INSTALL_PACKAGING_DEPS="0"
RUN_DOCS="1"
RUN_CODEQL="0"
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
    --flutter-dir)
      FLUTTER_DIR="${2:-}"
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
    --install-packaging-deps)
      INSTALL_PACKAGING_DEPS="${2:-}"
      shift 2
      ;;
    --strict-checks)
      STRICT_CHECKS="${2:-}"
      shift 2
      ;;
    --run-codeql)
      RUN_CODEQL="${2:-}"
      shift 2
      ;;
    --run-docs)
      RUN_DOCS="${2:-}"
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

if ! validate_non_empty "--app-name" "$APP_NAME"; then
  usage >&2
  exit 2
fi

STRICT_CHECKS="$(resolve_strict_checks "$STRICT_CHECKS")"

# Dynamische Wahl des Arbeitsverzeichnisses: /workspace (CI) oder lokal
REPO_ROOT="$(resolve_repo_root /workspace)"
if [[ "$REPO_ROOT" != "/workspace" ]]; then
  echo "[Info] /workspace nicht gefunden, benutze stattdessen $REPO_ROOT als Arbeitsverzeichnis."
fi
cd "$REPO_ROOT"

git_safe_dirs "$FLUTTER_DIR"
assert_flutter_available "$FLUTTER_DIR" || exit 2

if [[ "$MATRIX_ARCH" == "x64" ]] && maybe_truthy "$RUN_CODEQL"; then
  echo "[Warn] --run-codeql ist aktuell ein no-op im native Linux Flow und wird ignoriert."
fi

# Optional: Packaging-Dependencies installieren
if maybe_truthy "$INSTALL_PACKAGING_DEPS"; then
  setup_packaging_dependencies_for_container "$MATRIX_ARCH"
fi

# Ensure clang has a usable C++ runtime/toolchain setup in container builds.
setup_compiler_cache
export_toolchain_env "$MATRIX_ARCH"

# Check + Build + Packaging (delegiert an run-native-linux.sh)
run_command_with_packaging_runtime "$PACKAGE_FORMATS" \
  bash scripts/linux/run-native-linux.sh \
    --arch "$MATRIX_ARCH" \
    --build-mode "$BUILD_MODE" \
    --app-name "$APP_NAME" \
    --flutter-dir "$FLUTTER_DIR" \
    --package-formats "$PACKAGE_FORMATS" \
    --strict-checks "$STRICT_CHECKS" \
    --run-docs "$RUN_DOCS"
