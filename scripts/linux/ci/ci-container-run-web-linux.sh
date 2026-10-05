#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/container-steps.sh"
source "$SCRIPT_DIR/../lib/cli-common.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/linux/ci/ci-container-run-web-linux.sh [options]

Options:
  -a, --arch <x64|arm64>        Target architecture (required)
      --flutter-dir <path>      Flutter SDK directory (default: /opt/flutter, baked into the image)
      --strict-checks <bool>    Fail on format/analyze/test errors (default: true in CI, false locally)
      --run-codeql <bool>       Run CodeQL scan (default: false)
  -h, --help                    Show this help
EOF
}

MATRIX_ARCH=""
FLUTTER_DIR="/opt/flutter"
STRICT_CHECKS=""
RUN_CODEQL="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--arch)
      MATRIX_ARCH="${2:-}"
      shift 2
      ;;
    --flutter-dir)
      FLUTTER_DIR="${2:-}"
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

STRICT_CHECKS="$(resolve_strict_checks "$STRICT_CHECKS")"

# Dynamische Wahl des Arbeitsverzeichnisses: /workspace (CI) oder lokal
REPO_ROOT="$(resolve_repo_root /workspace)"
if [[ "$REPO_ROOT" != "/workspace" ]]; then
  echo "[Info] /workspace nicht gefunden, benutze stattdessen $REPO_ROOT als Arbeitsverzeichnis."
fi
cd "$REPO_ROOT"

# See lib/container-steps.sh for what this replaces.
flutter_lane_prepare_env "$FLUTTER_DIR" || exit 2

# Ensure clang has a usable C++ runtime/toolchain setup in container builds.
setup_compiler_cache
export_toolchain_env "$MATRIX_ARCH"

echo "=== Flutter doctor ==="
flutter doctor -v

echo "=== Dart checks: dependencies, format, analyze, test (in Chrome) ==="
# The native lanes keep the VM run; @TestOn('vm') marks the files that read the checkout.
run_flutter_common_checks "$STRICT_CHECKS" --extra-package third_party/ANThology --test-platform chrome

echo "=== Enable flutter web + Rust WASM toolchain ==="
# The image's dated nightly, the one its hub pin names; the floating channel would download every run.
web_nightly="$(sed -n 's/^RUST_NIGHTLY_TOOLCHAIN=//p' third_party/ANTfrastructure/linux/scripts/01-core/versions.env)"
: "${web_nightly:?no RUST_NIGHTLY_TOOLCHAIN in third_party/ANTfrastructure/linux/scripts/01-core/versions.env}"
# Guarded anyway: the image installs the components best-effort, and a bare host has none of it.
if ! rustup component list --toolchain "$web_nightly" 2>/dev/null | grep -q '^rust-src.*(installed)' ||
  ! rustup target list --toolchain "$web_nightly" 2>/dev/null | grep -q '^wasm32-unknown-unknown (installed)'; then
  rustup toolchain install "$web_nightly" --component rust-src --target wasm32-unknown-unknown
fi
# Defaulted: a bare host has no CARGO_HOME, and set -u would abort there.
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
# The image ships the codegen at FLUTTER_RUST_BRIDGE_VERSION; a bare host installs that pin, without --force.
command -v flutter_rust_bridge_codegen >/dev/null 2>&1 || cargo install --locked --version "${FLUTTER_RUST_BRIDGE_VERSION:?not set: the image exports it; on a bare host use the version pinned in third_party/OxidANT/Cargo.toml}" flutter_rust_bridge_codegen
flutter config --enable-web

echo "=== Build Web App ==="
flutter_rust_bridge_codegen build-web \
  --release \
  --rust-root third_party/OxidANT \
  --wasm-pack-rustup-toolchain "$web_nightly"
# Local CanvasKit, or an offline LAN host renders blank. See docs/source/project-operations.md § The web lane's CanvasKit source
flutter_build_web --wasm --no-web-resources-cdn

# Missing frb wasm artefacts do not fail the build; the page hangs at boot, so assert them here.
for artefact in pkg/oxidant.js pkg/oxidant_bg.wasm main.dart.wasm; do
  if [[ ! -s "build/web/${artefact}" ]]; then
    echo "Error: build/web/${artefact} is missing or empty after a successful build." >&2
    echo "       The page would load and then hang. Check the" >&2
    echo "       'flutter_rust_bridge_codegen build-web' step above." >&2
    exit 1
  fi
done

echo "=== Web build completed successfully ==="
