#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/ci-lane-libs.sh
source "$SCRIPT_DIR/../lib/ci-lane-libs.sh"
source "$SCRIPT_DIR/../lib/packaging-common.sh"

usage() {
  omni_ci_usage ci-container-run-native-linux arch-required build-mode-linux flutter-dir-image app-name-required package-formats-tar install-packaging-deps strict-checks run-codeql-refused run-docs help
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

omni_ci_require validate_arch "$MATRIX_ARCH"

omni_ci_require validate_non_empty "--app-name" "$APP_NAME"

STRICT_CHECKS="$(resolve_strict_checks "$STRICT_CHECKS")"

omni_ci_enter_workspace

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
mapfile -t lane_args < <(omni_ci_lane_args "$MATRIX_ARCH" "$BUILD_MODE" "$APP_NAME" "$FLUTTER_DIR")
app_packaging_run_command_with_runtime "$PACKAGE_FORMATS" \
  bash scripts/linux/ci/lane-native-linux.sh "${lane_args[@]}" \
    --package-formats "$PACKAGE_FORMATS" \
    --strict-checks "$STRICT_CHECKS" \
    --run-docs "$RUN_DOCS"

# What the persisted cache bought this run (reusable-linux.yml restores it).
dump_compiler_cache_stats || true
