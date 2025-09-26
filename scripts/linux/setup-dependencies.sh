#!/usr/bin/env bash
set -euo pipefail

# install_dependencies.sh
# Simple helper to install the packages you listed on a Debian/Ubuntu system.

SCRIPT_NAME=$(basename "$0")

print_usage() {
  cat <<EOF
Usage: $SCRIPT_NAME

Runs apt-get update and installs a set of development/runtime packages.
Run as a normal user (sudo is used inside) or as root.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_usage
  exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This system does not appear to have apt-get. Exiting." >&2
  exit 1
fi

# Update package lists
echo "[1/3] Updating package lists..."
sudo apt-get update -y

# Install requested packages (merged and deduplicated)
PACKAGES=(
  curl
  git
  unzip
  xz-utils
  zip
  libglu1-mesa
  clang
  cmake
  ninja-build
  pkg-config
  libgtk-3-dev
  liblzma-dev
  libstdc++-12-dev
)

echo "[2/3] Installing packages: ${PACKAGES[*]}"
sudo apt-get install -y "${PACKAGES[@]}"

# Cleanup apt cache to reduce image size (useful in containers)
echo "[3/3] Cleaning up..."
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

echo "All done. Packages installed successfully."
