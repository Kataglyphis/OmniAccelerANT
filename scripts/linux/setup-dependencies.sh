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

sudo apt-get update
sudo apt-get install -y sccache ccache cppcheck iwyu lcov binutils graphviz doxygen llvm valgrind

# for debian packaging
sudo apt-get install -y dpkg-dev fakeroot binutils

# Ensure pip is available
sudo apt-get install -y python3-pip

# Install latest CMake from Kitware APT repository
# Determine codename (e.g. focal, jammy). Fall back to 'noble' if lsb_release isn't available.
CODENAME=$(lsb_release -cs 2>/dev/null || echo "noble")
echo "Installing latest CMake via Kitware repo for codename: ${CODENAME}"

# Purge older distro cmake if present (ignore errors)
sudo apt-get purge --auto-remove -y cmake || true

# Ensure required tools for adding the repo are present
sudo apt-get update
sudo apt-get install -y wget gpg lsb-release ca-certificates

# Add Kitware GPG key (dearmored) and repository
wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null

echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ ${CODENAME} main" \
  | sudo tee /etc/apt/sources.list.d/kitware.list >/dev/null

sudo apt-get update
sudo apt-get install -y cmake

cmake --version

# desired tool versions
LLVM_WANTED=21        # for the apt.llvm.org helper (llvm.sh)
CLANG_WANTED=21       # for update-alternatives clang/clang++=21
export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# minimal prerequisites
sudo apt-get update
sudo apt-get install -y --no-install-recommends wget gnupg lsb-release ca-certificates

# Add the LLVM apt repo using the official helper (non-interactive)
wget -qO- https://apt.llvm.org/llvm.sh | sudo bash -s -- "${LLVM_WANTED}" all

sudo apt-get update

# clang
if [ -x "/usr/bin/clang-${CLANG_WANTED}" ]; then
  sudo update-alternatives --install /usr/bin/clang clang /usr/bin/clang-"${CLANG_WANTED}" 100
  sudo update-alternatives --set clang /usr/bin/clang-"${CLANG_WANTED}"
fi

# clang++
if [ -x "/usr/bin/clang++-${CLANG_WANTED}" ]; then
  sudo update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-"${CLANG_WANTED}" 100
  sudo update-alternatives --set clang++ /usr/bin/clang++-"${CLANG_WANTED}"
fi

# clang-tidy
if [ -x "/usr/bin/clang-tidy-${CLANG_WANTED}" ]; then
  sudo update-alternatives --install /usr/bin/clang-tidy clang-tidy /usr/bin/clang-tidy-"${CLANG_WANTED}" 100
fi

# clang-format
if [ -x "/usr/bin/clang-format-${CLANG_WANTED}" ]; then
  sudo update-alternatives --install /usr/bin/clang-format clang-format /usr/bin/clang-format-"${CLANG_WANTED}" 100
fi

# llvm-profdata
if [ -x "/usr/bin/llvm-profdata-${CLANG_WANTED}" ]; then
  sudo update-alternatives --install /usr/bin/llvm-profdata llvm-profdata /usr/bin/llvm-profdata-"${CLANG_WANTED}" 100
  sudo update-alternatives --set llvm-profdata /usr/bin/llvm-profdata-"${CLANG_WANTED}"
fi

# llvm-cov
if [ -x "/usr/bin/llvm-cov-${CLANG_WANTED}" ]; then
  sudo update-alternatives --install /usr/bin/llvm-cov llvm-cov /usr/bin/llvm-cov-"${CLANG_WANTED}" 100
  sudo update-alternatives --set llvm-cov /usr/bin/llvm-cov-"${CLANG_WANTED}"
fi

# Verify
clang --version
clang++ --version

# Install latest GCC
GCC_WANTED=14  # or 13, adjust as needed
sudo apt-get install -y --no-install-recommends \
  gcc-"${GCC_WANTED}" \
  g++-"${GCC_WANTED}" \
  gfortran-"${GCC_WANTED}"

# Set GCC as default using update-alternatives
if [ -x "/usr/bin/gcc-${GCC_WANTED}" ]; then
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-"${GCC_WANTED}" 100
  sudo update-alternatives --set gcc /usr/bin/gcc-"${GCC_WANTED}"
fi

if [ -x "/usr/bin/g++-${GCC_WANTED}" ]; then
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-"${GCC_WANTED}" 100
  sudo update-alternatives --set g++ /usr/bin/g++-"${GCC_WANTED}"
fi

if [ -x "/usr/bin/gcov-${GCC_WANTED}" ]; then
  sudo update-alternatives --install /usr/bin/gcov gcov /usr/bin/gcov-"${GCC_WANTED}" 100
  sudo update-alternatives --set gcov /usr/bin/gcov-"${GCC_WANTED}"
fi

# Verify
gcc --version
g++ --version

# Cleanup apt cache to reduce image size (useful in containers)
echo "[3/3] Cleaning up..."
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

echo "All done. Packages installed successfully."
