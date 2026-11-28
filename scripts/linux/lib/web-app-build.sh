#!/usr/bin/env bash
# The web app with its Rust wasm core, for the web lane and the docs site's /app/; needs container-steps.sh, run from the repo root.

# omni_web_app_build [flutter build web args...]: the wasm core into web/pkg, the app into build/web, then its fallback fonts.
omni_web_app_build() {
  local web_nightly artefact
  echo "=== Enable flutter web + Rust WASM toolchain ==="
  # The image's dated nightly, the one its hub pin names; the floating channel would download every run.
  web_nightly="$(sed -n 's/^RUST_NIGHTLY_TOOLCHAIN=//p' third_party/ANTfrastructure/linux/scripts/01-core/versions.env)"
  [[ -n "$web_nightly" ]] || {
    echo "Error: no RUST_NIGHTLY_TOOLCHAIN in third_party/ANTfrastructure/linux/scripts/01-core/versions.env" >&2
    return 1
  }
  # Guarded anyway: the image installs the components best-effort, and a bare host has none of it.
  if ! rustup component list --toolchain "$web_nightly" 2>/dev/null | grep -q '^rust-src.*(installed)' ||
    ! rustup target list --toolchain "$web_nightly" 2>/dev/null | grep -q '^wasm32-unknown-unknown (installed)'; then
    rustup toolchain install "$web_nightly" --component rust-src --target wasm32-unknown-unknown || return 1
  fi
  # Defaulted: a bare host has no CARGO_HOME, and set -u would abort there.
  export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
  # The image ships the codegen at FLUTTER_RUST_BRIDGE_VERSION; a bare host installs that pin, without --force.
  command -v flutter_rust_bridge_codegen >/dev/null 2>&1 ||
    cargo install --locked --version "${FLUTTER_RUST_BRIDGE_VERSION:?not set: the image exports it; on a bare host use the version pinned in third_party/OxidANT/Cargo.toml}" flutter_rust_bridge_codegen ||
    return 1
  flutter config --enable-web || return 1

  echo "=== Build Web App ==="
  flutter_rust_bridge_codegen build-web \
    --release \
    --rust-root third_party/OxidANT \
    --wasm-pack-rustup-toolchain "$web_nightly" || return 1
  # Local CanvasKit, or an offline LAN host renders blank. See docs/source/project-operations.md § The web lane's CanvasKit source
  flutter_build_web --wasm --no-web-resources-cdn "$@" || return 1
  python3 "$(antfrastructure_path linux/scripts/05-frameworks/flutter/fetch-fallback-fonts.py)" \
    --dest build/web/fallback-fonts || return 1

  # Missing wasm artefacts do not fail the build; the page hangs at boot, so assert them here.
  for artefact in pkg/oxidant.js pkg/oxidant_bg.wasm main.dart.wasm sqlite3.wasm; do
    if [[ ! -s "build/web/${artefact}" ]]; then
      echo "Error: build/web/${artefact} is missing or empty after a successful build." >&2
      echo "       The page would load and then hang. Check the" >&2
      echo "       'flutter_rust_bridge_codegen build-web' and sqlite3.wasm steps above." >&2
      return 1
    fi
  done
  # Last, so it reads every file the build wrote; the licences page shows it, and a file without an entry fails here.
  python3 -I scripts/licenses/web-license-inventory.py --write --app build/web || return 1
}
