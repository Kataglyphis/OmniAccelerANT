#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/ci-lane-libs.sh
source "$SCRIPT_DIR/../lib/ci-lane-libs.sh"
# shellcheck source=scripts/linux/lib/web-app-build.sh
source "$SCRIPT_DIR/../lib/web-app-build.sh"

usage() {
  omni_ci_usage ci-container-run-web-linux arch-required flutter-dir-image strict-checks run-codeql-refused help
}

MATRIX_ARCH=""
FLUTTER_DIR="/opt/flutter"
STRICT_CHECKS=""
RUN_CODEQL="0"

parse_omni_ci_options ci-container-run-web-linux "$@"

omni_ci_require validate_arch "$MATRIX_ARCH"

STRICT_CHECKS="$(resolve_strict_checks "$STRICT_CHECKS")"

if maybe_truthy "$RUN_CODEQL"; then
  echo "Error: --run-codeql true was requested, but the web Linux flow implements no CodeQL scan." >&2
  echo "       Pass --run-codeql false or implement the web scan before enabling it." >&2
  exit 2
fi

# Dynamische Wahl des Arbeitsverzeichnisses: /workspace (CI) oder lokal
omni_ci_enter_workspace

bash scripts/linux/tests/test-ci-options.sh

# See lib/container-steps.sh for what this replaces.
flutter_lane_prepare_env "$FLUTTER_DIR" || exit 2

# Ensure clang has a usable C++ runtime/toolchain setup in container builds.
setup_compiler_cache
export_toolchain_env "$MATRIX_ARCH"

echo "=== Flutter doctor ==="
flutter doctor -v

echo "=== The pinned sqlite3.wasm, against the lock ==="
bash "$(antfrastructure_path linux/scripts/05-frameworks/flutter/setup-sqlite3-wasm.sh)" "$PWD"
check_flutter_launcher_artifacts

echo "=== Dart checks: dependencies, format, analyze, test (in Chrome) ==="
# The native lanes keep the VM run; @TestOn('vm') marks the files that read the checkout.
run_flutter_common_checks "$STRICT_CHECKS" --extra-package third_party/ANThology --test-platform chrome

omni_web_app_build

echo "=== Smoke test: the build served, the shared web shell in place ==="
antfrastructure_source linux/scripts/01-core/http-readiness.sh
# A subshell, so the server's EXIT trap cannot replace setup_compiler_cache's sccache drain.
(
  python3 -m http.server 8080 --bind 127.0.0.1 --directory build/web >/dev/null 2>&1 &
  smoke_server=$!
  trap 'kill "$smoke_server" 2>/dev/null || true; wait "$smoke_server" 2>/dev/null || true' EXIT
  wait_for_http http://127.0.0.1:8080/ "http.server (pid $smoke_server)" || exit 1
  # No CSP here (the stream's hosts vary per board); CHECK_LOCAL_ENGINE fails on an engine from Google's CDN (owner, 2026-10-21: nothing from Google).
  REQUIRED_CSP_HOSTS="" CHECK_LOADING_SHELL=1 CHECK_LOCAL_ENGINE=1 CHECK_FALLBACK_FONTS=1 \
    bash "$(antfrastructure_path linux/webserver/scripts/flutter_integration_smoke_test.sh)" http://127.0.0.1:8080
)

echo "=== Browser smoke: all routes, local assets, no external hosts ==="
bash scripts/linux/check-web-browser.sh
bash scripts/linux/tests/test-check-web-browser.sh

echo "=== Browser smoke: the Stream page with nothing behind it backs off ==="
bash scripts/linux/check-web-browser.sh --empty

echo "=== Browser check: an explicit ObservANT address over http, mixed content, a refused local network ==="
bash scripts/linux/check-web-browser.sh --remote

echo "=== Web build completed successfully ==="
