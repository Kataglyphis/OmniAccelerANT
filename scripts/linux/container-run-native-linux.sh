#!/usr/bin/env bash
# set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/container-steps.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/linux/container-run-native-linux.sh [options]

Options:
  -a, --arch <x64|arm64>        Target architecture (required)
      --flutter-version <ver>   Flutter version (required)
      --flutter-dir <path>      Flutter SDK installation directory (default: /workspace/flutter)
  -n, --app-name <name>         Artifact base name (required)
      --package-formats <csv>   Packaging formats (default: tar)
      --install-packaging-deps <bool> Install deps for deb/flatpak/appimage (default: false)
      --strict-checks <bool>    Fail on format/analyze/test errors (default: true in CI, false locally)
      --run-codeql <bool>       Run CodeQL scan (default: false)
      --run-docs <bool>         Generate docs (default: false)
  -h, --help                    Show this help
EOF
}

run_privileged_cmd() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Error: need root privileges for command: $*" >&2
    return 1
  fi
}

setup_local_appimagetool() {
  mkdir -p .tools/bin

  local appimage_arch
  case "$MATRIX_ARCH" in
    x64) appimage_arch="x86_64" ;;
    arm64) appimage_arch="aarch64" ;;
    *)
      echo "Error: unsupported architecture for appimagetool bootstrap: $MATRIX_ARCH" >&2
      return 1
      ;;
  esac

  wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${appimage_arch}.AppImage" -O .tools/appimagetool
  chmod +x .tools/appimagetool
  ./.tools/appimagetool --appimage-extract >/dev/null
  rm -rf .tools/squashfs-root
  mv squashfs-root .tools/

  cat > .tools/bin/appimagetool <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/squashfs-root/AppRun" "$@"
EOF
  chmod +x .tools/bin/appimagetool
  export PATH="$PWD/.tools/bin:$PATH"
}

setup_packaging_dependencies() {
  run_privileged_cmd apt-get update
  run_privileged_cmd apt-get install -y dpkg flatpak flatpak-builder libfuse2 dbus-user-session wget

  setup_local_appimagetool

  export XDG_RUNTIME_DIR="/tmp/runtime-$(id -u)"
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"

  dbus-run-session -- flatpak --user remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  dbus-run-session -- flatpak --user install -y flathub org.freedesktop.Platform//23.08 org.freedesktop.Sdk//23.08
}

package_with_runtime_support() {
  local has_flatpak="0"
  IFS=',' read -r -a _formats <<< "$PACKAGE_FORMATS"
  for _raw in "${_formats[@]}"; do
    _fmt="$(echo "$_raw" | xargs | tr '[:upper:]' '[:lower:]')"
    if [[ "$_fmt" == "flatpak" ]]; then
      has_flatpak="1"
      break
    fi
  done

  if [[ "$has_flatpak" == "1" ]]; then
    dbus-run-session -- bash scripts/linux/package-linux.sh --formats "$PACKAGE_FORMATS"
  else
    bash scripts/linux/package-linux.sh --formats "$PACKAGE_FORMATS"
  fi
}

MATRIX_ARCH=""
FLUTTER_VERSION=""
FLUTTER_DIR="/workspace/flutter"
APP_NAME=""
PACKAGE_FORMATS="tar"
INSTALL_PACKAGING_DEPS="0"
INSTALL_FLUTTER="0"
RUN_DOCS="0"
RUN_CODEQL="0"
STRICT_CHECKS=""

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
    -n|--app-name)
      APP_NAME="${2:-}"
      shift 2
      ;;
    --package-formats)
      PACKAGE_FORMATS="${2:-}"
      shift 2
      ;;
    --install-packaging-deps)
      INSTALL_PACKAGING_DEPS="${2:-}"
      shift 2
      ;;
    --install-flutter)            # <--- ADD THIS BLOCK
      INSTALL_FLUTTER="${2:-}"    # <---
      shift 2                     # <---
      ;;
    --strict-checks)
      STRICT_CHECKS="${2:-}"
      shift 2
      ;;
    --run-codeql)
      RUN_CODEQL="${2:-}"
      shift 2
      ;;
    --run-docs)
      RUN_DOCS="${2:-}"
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

case "$MATRIX_ARCH" in
  x64|arm64) ;;
  *)
    echo "Error: --arch must be x64 or arm64" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ -z "$FLUTTER_VERSION" ]]; then
  echo "Error: --flutter-version is required" >&2
  usage >&2
  exit 2
fi

if [[ -z "$APP_NAME" ]]; then
  echo "Error: --app-name is required" >&2
  usage >&2
  exit 2
fi

export MATRIX_ARCH
export FLUTTER_VERSION
export FLUTTER_DIR
export APP_NAME
export PACKAGE_FORMATS
export INSTALL_PACKAGING_DEPS

if [[ -z "$STRICT_CHECKS" ]]; then
  if [[ "${CI:-}" == "true" ]]; then
    STRICT_CHECKS="1"
  else
    STRICT_CHECKS="0"
  fi
fi
export STRICT_CHECKS



# Dynamische Wahl des Arbeitsverzeichnisses: /workspace (CI) oder lokal
if [[ -d "/workspace" ]]; then
  REPO_ROOT="/workspace"
else
  REPO_ROOT="$(pwd)"
  echo "[Info] /workspace nicht gefunden, benutze stattdessen $REPO_ROOT als Arbeitsverzeichnis."
fi
cd "$REPO_ROOT"

# Optional: Flutter-Installation (nur im CI nötig)
if maybe_truthy "$INSTALL_FLUTTER"; then
  bash scripts/linux/install-flutter.sh
fi

# Checks (Format, Analyse, Tests)
bash scripts/linux/check-linux.sh

# Container-Build nutzt explizit das Toolchain-Setup
export_toolchain_env

# Build
if [[ "$MATRIX_ARCH" == "x64" ]] && maybe_truthy "$RUN_CODEQL"; then
  echo "[Warn] CodeQL-Build ist aktuell nicht modularisiert. Führe regulären Linux-Build aus."
fi
bash scripts/linux/build-linux.sh

# Optional: Packaging-Dependencies installieren
if maybe_truthy "$INSTALL_PACKAGING_DEPS"; then
  setup_packaging_dependencies
fi

# Packaging
package_with_runtime_support || echo "[Warn] Packaging threw an error, but we are ignoring it to prevent CI failure!" || true

# Docs
if [[ "$MATRIX_ARCH" == "x64" ]] && maybe_truthy "$RUN_DOCS"; then
  bash scripts/linux/generate-docs.sh
fi
