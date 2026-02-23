#!/usr/bin/env bash
set -euo pipefail

# Führt Checks und Tests für das Projekt aus
# Benötigte Umgebungsvariablen: FLUTTER_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/container-steps.sh"

source_bashrc_and_add_flutter_to_path
run_flutter_common_checks
