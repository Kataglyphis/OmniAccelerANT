#!/usr/bin/env bash
set -euo pipefail

# Führt Checks und Tests für das Projekt aus

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/container-steps.sh"
source "$SCRIPT_DIR/cli-common.sh"

usage() {
	cat <<'EOF'
Usage:
	bash scripts/linux/lib/check-linux.sh [--flutter-dir <path>] [--strict-checks <bool>]
EOF
}

FLUTTER_DIR=""
STRICT_CHECKS=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--flutter-dir)
			FLUTTER_DIR="${2:-}"
			shift 2
			;;
		--strict-checks)
			STRICT_CHECKS="${2:-}"
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

STRICT_CHECKS="$(resolve_strict_checks "$STRICT_CHECKS")"

source_bashrc_and_add_flutter_to_path "$FLUTTER_DIR"
run_flutter_common_checks "$STRICT_CHECKS"
