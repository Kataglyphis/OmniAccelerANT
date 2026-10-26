#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$SCRIPT_DIR/../lib/cli-common.sh"
source "$SCRIPT_DIR/../lib/ci-options.sh"
source "$SCRIPT_DIR/../lib/container-steps.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/linux/ci/lane-native-linux.sh [options]

Options:
  -a, --arch <x64|arm64>        Target architecture (default: auto-detect)
  --build-mode <debug|profile|release> Build mode for flutter build linux (default: release)
  -n, --app-name <name>         Artifact base name (default: pubspec name)
      --package-formats <csv>   Packaging formats (default: tar,appimage,flatpak,deb)
      --no-package              Build only (skip packaging)
      --strict-checks <bool>    Fail on format/analyze/test errors (default: true in CI, false locally)
      --run-docs <bool>         Run generate-docs.sh, x64 only (default: false; docs.yml builds the site)
      --flutter-dir <path>      Optional Flutter SDK directory (uses <path>/bin/flutter)
  -h, --help                    Show this help

Notes:
  - The native lane's body: ci-container-run-native-linux.sh runs it inside the CI image, agentic-build.sh too. It starts no container.
  - Requires flutter + dart available (either on PATH or via --flutter-dir).
EOF
}

APP_NAME="$(resolve_app_name)"
MATRIX_ARCH="$(detect_arch)"
BUILD_MODE="release"
FLUTTER_DIR=""
PACKAGE_FORMATS="tar,appimage,flatpak,deb"
RUN_PACKAGING=1
RUN_DOCS="0"
STRICT_CHECKS=""

parse_omni_ci_options lane-native-linux "$@"

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

# One batch: every gate runs and assert_gates fails once; --strict-checks governs only the Dart half.
gate_reset "code quality (${MATRIX_ARCH})"
run_gate "CI option parser tests" bash scripts/linux/tests/test-ci-options.sh
run_gate "bundle option parser tests" bash scripts/linux/tests/test-bundle-options.sh
# The checks' one test run writes the coverage the floor below reads; a second run cost 55 s.
dart_lcov="build/coverage/lcov.info"
rm -f "$dart_lcov"
run_gate "flutter checks" run_flutter_common_checks "$STRICT_CHECKS" --coverage "$dart_lcov"
run_gate "cmake-format --check" run_cmake_format_check
# The plugin's C++ against its .clang-format, graded only by LLVM_RELEASE's clang-format; its suite plants a deviation.
run_gate "plugin clang-format --check" bash scripts/linux/check-plugin-cpp-format.sh
run_gate "plugin format gate tests" bash scripts/linux/tests/test-check-plugin-cpp-format.sh
# The bundle gate's own mutation suite (synthetic ELFs, no build needed): when G6 runs, and that it decides.
run_gate "bundle gate tests" bash scripts/linux/tests/test-check-bundle-closure.sh
run_gate "bundle element gate tests" bash scripts/linux/tests/test-check-bundle-gst-elements.sh
run_gate "rust toolchain gate tests" bash scripts/linux/tests/test-check-rust-toolchain.sh
# lib/ was 97.2 % covered on 2026-10-16 (87.4 % on 2026-10-12); raise the floor as it climbs.
run_gate "dart coverage" bash "$(antfrastructure_path linux/scripts/05-frameworks/flutter/check-dart-coverage.sh)" \
  --min 96 --lcov "$dart_lcov" --exclude lib/src/rust/
# Title vs manifest, sqlite3.wasm vs the hub's pin, 8-bit icons: what no build step checks.
run_gate "web artefacts" python3 "$(antfrastructure_path linux/scripts/05-frameworks/flutter/check-web-artefacts.py)" --repo-root .
assert_gates

flutter config --enable-linux-desktop

# Models are not tracked; the debug app the integration tests build loads OxidANT's checkout copy.
bash third_party/OxidANT/scripts/linux/fetch-models.sh

# linux/CMakeLists.txt reads it at configure time: the plugin's gtest target, built only by run_plugin_gtest.
export KATAGLYPHIS_PLUGIN_TESTS=1

# Clean and build (pub get already done above, skip duplicate call)
flutter clean
flutter build linux --"$BUILD_MODE"

# Release-only closure and gates before packaging. See docs/source/camera-streaming.md § Relocatable Linux bundles
if [[ "$BUILD_MODE" == "release" ]]; then
  bash scripts/linux/bundle-runtime-closure.sh --arch "$MATRIX_ARCH" --build-mode "$BUILD_MODE"

  build_dir="build/linux/${MATRIX_ARCH}/${BUILD_MODE}"
  gate_reset "bundle checks (${MATRIX_ARCH})"
  run_gate "knt ABI" bash scripts/linux/check-knt-abi.sh --arch "$MATRIX_ARCH" --build-mode "$BUILD_MODE"
  run_gate "runtime closure" bash scripts/linux/check-bundle-closure.sh --arch "$MATRIX_ARCH" --build-mode "$BUILD_MODE"
  # The app loads no distro plugin, so an element no bundled plugin provides is missing on every user machine.
  run_gate "bundled GStreamer elements" bash scripts/linux/check-bundle-gst-elements.sh --arch "$MATRIX_ARCH" --build-mode "$BUILD_MODE"
  run_gate "plugin gtest" run_plugin_gtest "$build_dir"
  run_gate "rust toolchain" bash scripts/linux/check-rust-toolchain.sh "${build_dir}/bundle/lib/liboxidant.so"
  assert_gates

  # Under the image's xvfb-run: the packaged bundle starts, and the app drives its integration test.
  gate_reset "app under Xvfb (${MATRIX_ARCH})"
  run_gate "launch smoke" run_launch_smoke "${build_dir}/bundle/$(linux_binary_name)"
  run_gate "launch smoke, bundled glibc" run_bundled_glibc_launch_smoke "${build_dir}/bundle/$(linux_binary_name)"
  run_gate "integration test" run_integration_test
  # Rust -> knt_push_frame -> texture with a test pattern: CI has no camera, and the push path needs none.
  run_gate "webcam frame test" run_integration_test integration_test/webcam_frame_test.dart
  # One arch is enough to track the Dart side, and a profile build costs minutes.
  if [[ "$MATRIX_ARCH" == "x64" ]]; then
    run_gate "frontend performance" run_frontend_performance
  fi
  assert_gates
else
  echo "Info: runtime closure and bundle gates are release-only (build-mode is '$BUILD_MODE')."
fi

if [[ "$RUN_PACKAGING" -eq 1 && "$BUILD_MODE" == "release" ]]; then
  _strict_package_arg=()
  if maybe_truthy "$STRICT_CHECKS"; then
    _strict_package_arg+=(--strict)
  fi
  bash scripts/linux/package-linux.sh --arch "$MATRIX_ARCH" --app-name "$APP_NAME" --formats "$PACKAGE_FORMATS" "${_strict_package_arg[@]}"
  if [[ ",${PACKAGE_FORMATS}," == *,flatpak,* ]]; then
    gate_reset "app flatpak under Xvfb (${MATRIX_ARCH})"
    run_gate "flatpak launch smoke" run_flatpak_launch_smoke "$APP_NAME"
    assert_gates
  fi
elif [[ "$RUN_PACKAGING" -eq 1 ]]; then
  echo "Info: packaging skipped because --build-mode is '$BUILD_MODE' (packaging is release-only)."
else
  echo "Info: packaging skipped (--no-package)."
fi

# Docs
case "${RUN_DOCS,,}" in
  1|true|yes|y|on)
    if [[ "$MATRIX_ARCH" == "x64" ]]; then
      bash scripts/linux/generate-docs.sh
    else
      echo "Info: docs generation is only enabled on x64; skipping for arch '$MATRIX_ARCH'."
    fi
    ;;
esac
