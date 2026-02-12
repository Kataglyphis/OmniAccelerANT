#!/usr/bin/env bash
set -e  # exit on any error

# NOTE: Keep LF line endings for Linux shells.

# ------------------------------------------
# Setup Flutter SDK on ARM64 (Linux)
# ------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./setup-flutter-common.sh

source "${SCRIPT_DIR}/setup-flutter-common.sh"

# Allow passing version and install directory as arguments

FLUTTER_VERSION="${1:-3.41.0}"  # default if not provided
FLUTTER_DIR="${2:-/opt}"        # default if not provided

setup_flutter "ARM64" "${FLUTTER_VERSION}" "${FLUTTER_DIR}"