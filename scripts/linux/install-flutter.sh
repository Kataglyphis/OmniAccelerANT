#!/usr/bin/env bash
set -euo pipefail

# Installiert Flutter SDK für die gewünschte Architektur und Version
# Benötigte Umgebungsvariablen: FLUTTER_VERSION, FLUTTER_DIR, MATRIX_ARCH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/container-steps.sh"

setup_flutter_sdk
