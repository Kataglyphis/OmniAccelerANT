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
      --flutter-version <ver>   Flutter version (required)
      --flutter-dir <path>      Flutter SDK installation directory (default: /workspace/flutter)
      --install-flutter <bool>  Install Flutter SDK (default: false)
      --strict-checks <bool>    Fail on format/analyze/test errors (default: true in CI, false locally)
      --run-codeql <bool>       Run CodeQL scan (default: false)
  -h, --help                    Show this help
EOF
}

MATRIX_ARCH=""
FLUTTER_VERSION=""
FLUTTER_DIR="/workspace/flutter"
INSTALL_FLUTTER="0"
STRICT_CHECKS=""
RUN_CODEQL="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--arch)
      MATRIX_ARCH="${2:-}"
      shift 2
      ;;
    --flutter-version)
      FLUTTER_VERSION="${2:-}"
      shift 2
      ;;
    --flutter-dir)
      FLUTTER_DIR="${2:-}"
      shift 2
      ;;
    --install-flutter)
      INSTALL_FLUTTER="${2:-}"
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

# CI passes no --flutter-version: resolve it, and its matching sha256, from
# ContainerHub's versions.env (resolve_flutter_pin, ../lib/container-steps.sh).
# This lane does not source packaging-common.sh, so exporting the sha here is
# what stops setup-flutter.sh falling back to the image's baked versions.env.
if [[ -z "$FLUTTER_VERSION" ]]; then
  resolve_flutter_pin || exit 2
fi

if ! validate_non_empty "--flutter-version" "$FLUTTER_VERSION"; then
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

# Optional: Flutter-Installation (nur im CI nötig)
if maybe_truthy "$INSTALL_FLUTTER"; then
  bash scripts/linux/lib/install-flutter.sh --flutter-version "$FLUTTER_VERSION" --flutter-dir "$FLUTTER_DIR" --arch "$MATRIX_ARCH"
fi

# Add Flutter to PATH
source_bashrc_and_add_flutter_to_path "$FLUTTER_DIR"
git_safe_dirs "$FLUTTER_DIR"

# Ensure clang has a usable C++ runtime/toolchain setup in container builds.
export_toolchain_env

echo "=== Flutter doctor ==="
flutter doctor -v

echo "=== Dart checks: dependencies, format, analyze, test ==="
run_flutter_common_checks "$STRICT_CHECKS" --extra-package ExternalLib/jotrockenmitlockenrepo

echo "=== Enable flutter web + Rust WASM toolchain ==="
#rustup component add rust-src --toolchain nightly-x86_64-unknown-linux-gnu || true
#rustup target add wasm32-unknown-unknown --toolchain nightly || true
# No `|| true`: the failure used to resurface as an opaque "command not found".
# The lane overrides CARGO_HOME, so its bin dir is not the one on PATH.
cargo install flutter_rust_bridge_codegen
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
flutter config --enable-web

echo "=== Build Web App ==="
flutter_rust_bridge_codegen build-web \
  --release \
  --rust-root ExternalLib/Kataglyphis-RustProjectTemplate
flutter build web --release --wasm

echo "=== Web build completed successfully ==="
