#!/usr/bin/env bash
set -e  # exit on any error
# NOTE: Keep LF line endings for Linux shells.

# ------------------------------------------
# Setup Flutter SDK on ARM64 (Linux)
# ------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./setup-flutter-common.sh
source "${SCRIPT_DIR}/setup-flutter-common.sh"

# Allow passing version as an argument
FLUTTER_VERSION="${1:-3.38.9}"  # default if not provided

setup_flutter "ARM64" "${FLUTTER_VERSION}"
