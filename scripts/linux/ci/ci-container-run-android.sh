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

REPO_ROOT="$(resolve_repo_root /workspace)"
cd "$REPO_ROOT"

git_safe_dirs "$FLUTTER_DIR"

assert_flutter_available "$FLUTTER_DIR" || exit 2
source_bashrc_and_add_flutter_to_path "$FLUTTER_DIR"

# Container-only preparation. None of this exists on a developer machine, which
# is why it lives here and is NOT pushed down into run-android.sh.
#
# A one-gate batch and not a bare call: assert_gates is what turns a recorded
# failure back into an exit code, and it is also what refuses to report green
# over an empty batch, so a future second container-only check joins this list
# instead of growing another accumulator. The lane's OTHER check,
# run_flutter_common_checks, cannot join it: it runs only in the CodeQL branch
# below, and in the other branch run-android.sh runs its own copy.
# This gate no longer honours STRICT_CHECKS — it used to run here and discard
# its verdict; see run_cmake_format_check in lib/container-steps.sh.
gate_reset "code quality"
run_gate "cmake-format --check" run_cmake_format_check
assert_gates
setup_compiler_cache
export_android_gstreamer_env
export_toolchain_env "$MATRIX_ARCH"

if maybe_truthy "$RUN_CODEQL"; then
  # CodeQL performs the APK build ITSELF: codeql_write_build_script wraps
  # `flutter build apk --<mode>` and codeql_create_db_cluster runs it as the
  # database's build command. run-android.sh's build cannot be reused inside
  # that, so the checks it would have run are run explicitly here instead --
  # run_flutter_common_checks is the same flutter_checks.sh --strict false call
  # that run-android.sh makes.
  run_flutter_common_checks "$STRICT_CHECKS"
  # Bare, like run-android.sh:90 and the web lane's `flutter config
  # --enable-web`: this is a configuration step, not a check. It used to run
  # through run_check_cmd, which in this lane (STRICT_CHECKS is pinned to 0
  # above) meant `flutter config --enable-android || true` — a failure here was
  # discarded and resurfaced as an unexplained failure in the APK build that
  # CodeQL drives below.
  flutter config --enable-android

  # No fallback build. This used to catch a CodeQL failure, print a warning and
  # build a plain APK, so the only real security scan in this repository could
  # fail end to end while the lane stayed green and shipped an artifact. Under
  # `set -e` the failure now ends the run, which is the gate working.
  run_codeql_android "$FLUTTER_DIR" "$BUILD_MODE"

  if [[ "$BUILD_MODE" == "release" ]]; then
    package_android_apk_outputs_tar "$MATRIX_ARCH" "$APP_NAME"
  else
    echo "Info: packaging skipped because --build-mode is '$BUILD_MODE' (packaging is release-only)."
  fi
else
  # Delegate to the entry point the owner runs by hand -- checks, config,
  # clean/pub get/build apk and packaging all live there. This is the same
  # shape ci-container-run-native-linux.sh uses for run-native-linux.sh, and it
  # is what keeps the CI path and the local path from drifting: the build body
  # used to be copied into this file and the two copies had already diverged.
  bash "$REPO_ROOT/scripts/linux/run-android.sh" \
    --arch "$MATRIX_ARCH" \
    --build-mode "$BUILD_MODE" \
    --app-name "$APP_NAME" \
    --flutter-dir "$FLUTTER_DIR"
fi
