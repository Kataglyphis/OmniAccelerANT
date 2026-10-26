#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/container-steps.sh"
source "$SCRIPT_DIR/../lib/cli-common.sh"
source "$SCRIPT_DIR/../lib/ci-options.sh"
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
      --install-packaging-deps <bool> Install the flathub runtime; only consulted when --package-formats has flatpak (default: false)
      --strict-checks <bool>    Fail on format/analyze/test errors (default: true in CI, false locally)
      --run-codeql <bool>       Must be false: no CodeQL scan is implemented here
      --run-docs <bool>         Run generate-docs.sh, x64 only (default: false; docs.yml builds the site)
  -h, --help                    Show this help
EOF
}

MATRIX_ARCH=""
BUILD_MODE="release"
FLUTTER_DIR="/opt/flutter"
APP_NAME=""
PACKAGE_FORMATS="tar"
INSTALL_PACKAGING_DEPS="0"
RUN_DOCS="0"
RUN_CODEQL="0"
STRICT_CHECKS=""

parse_omni_ci_options ci-container-run-native-linux "$@"

if ! validate_arch "$MATRIX_ARCH"; then
  usage >&2
  exit 2
fi

if ! validate_non_empty "--app-name" "$APP_NAME"; then
  usage >&2
  exit 2
fi

STRICT_CHECKS="$(resolve_strict_checks "$STRICT_CHECKS")"

REPO_ROOT="$(resolve_repo_root /workspace)"
if [[ "$REPO_ROOT" != "/workspace" ]]; then
  echo "[Info] /workspace nicht gefunden, benutze stattdessen $REPO_ROOT als Arbeitsverzeichnis."
fi
cd "$REPO_ROOT"

# See lib/container-steps.sh for what this replaces.
flutter_lane_prepare_env "$FLUTTER_DIR" || exit 2

# Refused, not warned: the native flow has no CodeQL scan, and a silent skip would read as success.
if maybe_truthy "$RUN_CODEQL"; then
  echo "Error: --run-codeql true was requested, but the native Linux flow implements no CodeQL scan." >&2
  echo "       Pass --run-codeql false, or implement it (see scripts/linux/codeql/codeql-android.sh" >&2
  echo "       for the shape the android lane uses)." >&2
  exit 2
fi

# Only a requested flatpak needs the ~1.9 GB flathub runtimes. See docs/source/project-operations.md § The Linux lanes, run locally
if ! app_packaging_formats_include_flatpak "$PACKAGE_FORMATS"; then
  echo "[Info] No flatpak in --package-formats '${PACKAGE_FORMATS}'; skipping the flathub runtime install."
elif maybe_truthy "$INSTALL_PACKAGING_DEPS"; then
  app_packaging_setup_dependencies_for_container "$MATRIX_ARCH"
fi

# Ensure clang has a usable C++ runtime/toolchain setup in container builds.
setup_compiler_cache
export_toolchain_env "$MATRIX_ARCH"
setup_linker

# Checks, build and packaging live in lane-native-linux.sh.
app_packaging_run_command_with_runtime "$PACKAGE_FORMATS" \
  bash scripts/linux/ci/lane-native-linux.sh \
    --arch "$MATRIX_ARCH" \
    --build-mode "$BUILD_MODE" \
    --app-name "$APP_NAME" \
    --flutter-dir "$FLUTTER_DIR" \
    --package-formats "$PACKAGE_FORMATS" \
    --strict-checks "$STRICT_CHECKS" \
    --run-docs "$RUN_DOCS"

# What the persisted cache bought this run (reusable-linux.yml restores it).
dump_compiler_cache_stats || true
