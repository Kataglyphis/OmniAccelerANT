#!/usr/bin/env bash
# set -euo pipefail

# Baut das Linux-Release mit Flutter
# Benötigte Umgebungsvariablen: FLUTTER_DIR, MATRIX_ARCH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/container-steps.sh"

source_bashrc_and_add_flutter_to_path

flutter clean
flutter pub get
flutter build linux --release
