#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=scripts/linux/lib/ci-lane-libs.sh
source "$SCRIPT_DIR/../lib/ci-lane-libs.sh"
source "$SCRIPT_DIR/../lib/packaging-common.sh"

usage() {
  omni_ci_usage lane-android arch-label-auto build-mode-apk app-name-apk flutter-dir-optional emulator-smoke help
  omni_ci_lane_notes "The android lane's body: ci-container-run-android.sh runs it inside the CI image. It starts no container."
}

APP_NAME="$(resolve_app_name)-apk"
MATRIX_ARCH="$(detect_arch)"
BUILD_MODE="release"
FLUTTER_DIR=""
EMULATOR_SMOKE="false"

parse_omni_ci_options lane-android "$@"

omni_ci_validate_lane_args "$APP_NAME" "$MATRIX_ARCH" "$BUILD_MODE" || exit 2

ensure_flutter_bin_on_path "$FLUTTER_DIR"

cd "$REPO_ROOT"

require_cmd flutter
require_cmd dart

# The hub's pub get + format + analyze + test plus the plugin's Dart tests, strict like every lane (AGENTS.md § 5).
run_flutter_common_checks true
check_flutter_launcher_artifacts

flutter config --enable-android

flutter clean
flutter pub get
# android-arm64 is Flutter's name for kataglyphisAbi (android/build.gradle.kts): no libapp, Rust or sqlite3 for a dropped ABI.
flutter build apk --"$BUILD_MODE" --target-platform android-arm64
verify_flutter_package_license "build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk" '*flutter_assets/NOTICES.Z'
check_native_license_coverage "build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk" android
bash "$REPO_ROOT/scripts/linux/check-apk-abi.sh" --apk "build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk"
bash "$REPO_ROOT/scripts/linux/check-rust-toolchain.sh" --apk "build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk"

# The plugin's JVM test, fatal on purpose; Gradle is warm from the apk build, so it costs little.
(cd android && ./gradlew :kataglyphis_native_inference:testDebugUnitTest --console=plain)

if maybe_truthy "$EMULATOR_SMOKE"; then
  application_id="$(sed -n 's/^[[:space:]]*applicationId = "\(.*\)"/\1/p' android/app/build.gradle.kts | tr -d '\r' | head -n 1)"
  bash "$REPO_ROOT/scripts/linux/check-apk-on-emulator.sh" \
    --apk "build/app/outputs/flutter-apk/app-${BUILD_MODE}.apk" --package "$application_id"
fi

if [[ "$BUILD_MODE" == "release" ]]; then
  app_packaging_package_android_apk_outputs_tar "$MATRIX_ARCH" "$APP_NAME"
else
  echo "Info: packaging skipped because --build-mode is '$BUILD_MODE' (packaging is release-only)."
fi
