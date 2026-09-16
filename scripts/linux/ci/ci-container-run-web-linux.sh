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

echo "=== Dart checks: dependencies, format, analyze, test ==="
run_flutter_common_checks "$STRICT_CHECKS" --extra-package third_party/ANThology

echo "=== Enable flutter web + Rust WASM toolchain ==="
# build-web runs wasm-pack with `-Z build-std=std,panic_abort`, which needs the
# nightly toolchain plus rust-src — AGENTS.md § 4.
#
# Guarded, not unconditional. `rustup toolchain install nightly` is NOT a no-op
# when nightly is already present: it UPDATES it, and on any day the image's
# baked nightly is not the newest one that update renames files out of a
# read-only image layer and dies with "Invalid cross-device link (os error 18)".
# Same shape as the `command -v flutter_rust_bridge_codegen` guard below: ask
# whether the thing is there, install only if it is not. Details and the other
# two candidate fixes: BACKLOG.md, "the web lane's rustup step".
if ! rustup component list --toolchain nightly 2>/dev/null | grep -q '^rust-src.*(installed)' ||
  ! rustup target list --toolchain nightly 2>/dev/null | grep -q '^wasm32-unknown-unknown (installed)'; then
  rustup toolchain install nightly --component rust-src --target wasm32-unknown-unknown
fi
# CARGO_HOME is exported by the image; a bare host has it unset, and this file
# runs under `set -euo pipefail`, so without the default the guard below aborts
# on the very host it exists to serve.
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
# The image ships the codegen at FLUTTER_RUST_BRIDGE_VERSION
# (third_party/ANTfrastructure/docs/consumer-image-contract.md, "The web lane
# toolchain"); a bare-host run
# installs the same pin. No `|| true` (it hid a "command not found") and no
# --force (--force rebuilds 174 crates per run of a lane that has the binary).
command -v flutter_rust_bridge_codegen >/dev/null 2>&1 || cargo install --locked --version "${FLUTTER_RUST_BRIDGE_VERSION:?not set: the image exports it; on a bare host use the version pinned in third_party/OxidANT/Cargo.toml}" flutter_rust_bridge_codegen
flutter config --enable-web

echo "=== Build Web App ==="
flutter_rust_bridge_codegen build-web \
  --release \
  --rust-root third_party/OxidANT
# --no-web-resources-cdn is load-bearing and the reason is invisible here: the
# flag defaults ON and bakes https://www.gstatic.com/flutter-canvaskit/<rev>
# into the loader AND a dart-define, so a host with no route to gstatic renders
# a blank page — which is exactly the cat-stream runbook's Pi-on-a-LAN.
# Verify with `grep -o '"useLocalCanvasKit":[a-z]*' build/web/flutter_bootstrap.js`
# (must print true; the key is emitted only when true). Do NOT verify by
# grepping gstatic — one inert hit survives in flutter.js and
# flutter_bootstrap.js by design. Why, and the measurement:
# docs/source/project-operations.md § The web lane's CanvasKit source.
flutter_build_web --wasm --no-web-resources-cdn

# A build that is missing the frb wasm artefacts does not fail — it HANGS in the
# browser. frb's web loader appends a <script> for pkg/oxidant.js and awaits its
# onLoad; a 404 fires `error` instead, so the await never completes, RustLib.init
# never returns, runApp is never reached, and the visitor gets the boot spinner
# forever with one 404 in the console and no Dart exception. Nothing downstream
# can detect that, so the lane asserts the artefacts exist instead of shipping a
# page that cannot start. build/web/pkg/ comes from the codegen step above.
for artefact in pkg/oxidant.js pkg/oxidant_bg.wasm main.dart.wasm; do
  if [[ ! -s "build/web/${artefact}" ]]; then
    echo "Error: build/web/${artefact} is missing or empty after a successful build." >&2
    echo "       The page would load and then hang. Check the" >&2
    echo "       'flutter_rust_bridge_codegen build-web' step above." >&2
    exit 1
  fi
done

echo "=== Web build completed successfully ==="
