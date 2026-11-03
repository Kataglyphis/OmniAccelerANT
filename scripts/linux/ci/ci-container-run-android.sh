#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/ci-lane-libs.sh
source "$SCRIPT_DIR/../lib/ci-lane-libs.sh"
source "$SCRIPT_DIR/../lib/packaging-common.sh"
source "$SCRIPT_DIR/../codeql/codeql-common.sh"
source "$SCRIPT_DIR/../codeql/codeql-android.sh"

usage() {
  omni_ci_usage ci-container-run-android arch-label-required build-mode-apk-image flutter-dir-image app-name-required emulator-smoke run-codeql-manual help
}

MATRIX_ARCH=""
BUILD_MODE="release"
FLUTTER_DIR="/opt/flutter"
APP_NAME=""
RUN_CODEQL="0"
EMULATOR_SMOKE="false"

parse_omni_ci_options ci-container-run-android "$@"

omni_ci_require validate_arch "$MATRIX_ARCH"

omni_ci_require omni_ci_validate_build_mode "$BUILD_MODE"


omni_ci_require validate_non_empty "--app-name" "$APP_NAME"

# Strict, as in lane-android.sh: a failing Dart check reds this lane like the others (AGENTS.md § 5).
STRICT_CHECKS="1"

REPO_ROOT="$(resolve_repo_root /workspace)"
cd "$REPO_ROOT"

# PATH, safe.directory, PUB_CACHE and `flutter --version` in one upstream call.
flutter_lane_prepare_env "$FLUTTER_DIR" || exit 2

# Container-only preparation, kept out of lane-android.sh; a batch so assert_gates turns a failure into the exit code.
gate_reset "code quality"
run_gate "CI option parser tests" bash scripts/linux/tests/test-ci-options.sh
run_gate "Flutter package license tests" bash scripts/linux/tests/test-flutter-package-license.sh
run_gate "third-party license tests" bash scripts/linux/tests/test-third-party-licenses.sh
run_gate "brand icon tests" bash scripts/linux/tests/test-check-brand-icons.sh
run_gate "cmake-format --check" run_cmake_format_check
# The APK ABI gate's own suite (synthetic APKs): that it refuses an extra slice or a missing plugin.
run_gate "apk abi gate tests" bash scripts/linux/tests/test-check-apk-abi.sh
run_gate "rust toolchain gate tests" bash scripts/linux/tests/test-check-rust-toolchain.sh
run_gate "emulator gate tests" bash scripts/linux/tests/test-check-apk-on-emulator.sh
assert_gates
setup_compiler_cache
export_toolchain_env "$MATRIX_ARCH"

if maybe_truthy "$RUN_CODEQL"; then
  # CodeQL drives the APK build itself, so lane-android.sh's checks run here instead.
  run_flutter_common_checks "$STRICT_CHECKS"
  check_flutter_launcher_artifacts
  flutter config --enable-android

  # No fallback build: a failed scan must fail the lane, not ship a plain APK.
  run_codeql_android "$FLUTTER_DIR" "$BUILD_MODE"
  verify_flutter_package_license "build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk" '*flutter_assets/NOTICES.Z'
  check_native_license_coverage "build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk" android
  bash "$REPO_ROOT/scripts/linux/check-apk-abi.sh" --apk "build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk"
  bash "$REPO_ROOT/scripts/linux/check-rust-toolchain.sh" --apk "build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk"

  if [[ "$BUILD_MODE" == "release" ]]; then
    app_packaging_package_android_apk_outputs_tar "$MATRIX_ARCH" "$APP_NAME"
  else
    echo "Info: packaging skipped because --build-mode is '$BUILD_MODE' (packaging is release-only)."
  fi
else
  # The same entry point a developer runs, so the CI and local paths cannot drift.
  mapfile -t lane_args < <(omni_ci_lane_args "$MATRIX_ARCH" "$BUILD_MODE" "$APP_NAME" "$FLUTTER_DIR")
  bash "$REPO_ROOT/scripts/linux/ci/lane-android.sh" "${lane_args[@]}" \
    --emulator-smoke "$EMULATOR_SMOKE"
fi
