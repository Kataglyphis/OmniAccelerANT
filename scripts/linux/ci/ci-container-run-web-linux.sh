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

assert_flutter_available "$FLUTTER_DIR" || exit 2
source_bashrc_and_add_flutter_to_path "$FLUTTER_DIR"
git_safe_dirs "$FLUTTER_DIR"

# Ensure clang has a usable C++ runtime/toolchain setup in container builds.
setup_compiler_cache
export_toolchain_env "$MATRIX_ARCH"

echo "=== Flutter doctor ==="
flutter doctor -v

echo "=== Dart checks: dependencies, format, analyze, test ==="
run_flutter_common_checks "$STRICT_CHECKS" --extra-package third_party/jotrockenmitlockenrepo

echo "=== Enable flutter web + Rust WASM toolchain ==="
# build-web runs wasm-pack with `-Z build-std=std,panic_abort`, which needs the
# nightly toolchain plus rust-src. Installed explicitly rather than left to
# rustup's auto-install, which rustup itself deprecates. Idempotent, and a
# no-op once the image ships them — AGENTS.md § 3.
rustup toolchain install nightly --component rust-src --target wasm32-unknown-unknown
# No `|| true`: the failure used to resurface as an opaque "command not found".
# cargo install writes into CARGO_HOME/bin, which need not be on PATH.
cargo install flutter_rust_bridge_codegen
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
flutter config --enable-web

echo "=== Build Web App ==="
flutter_rust_bridge_codegen build-web \
  --release \
  --rust-root third_party/RustProjectTemplate
flutter build web --release --wasm

echo "=== Web build completed successfully ==="
