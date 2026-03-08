#!/usr/bin/env bash
set -euo pipefail

# Installiert Flutter SDK für die gewünschte Architektur und Version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/container-steps.sh"
source "$SCRIPT_DIR/cli-common.sh"

usage() {
	cat <<'EOF'
Usage:
	bash scripts/linux/lib/install-flutter.sh --flutter-version <ver> [--flutter-dir <path>] --arch <x64|arm64>
EOF
}

FLUTTER_VERSION=""
FLUTTER_DIR="/workspace/flutter"
MATRIX_ARCH=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--flutter-version)
			FLUTTER_VERSION="${2:-}"
			shift 2
			;;
		--flutter-dir)
			FLUTTER_DIR="${2:-}"
			shift 2
			;;
		-a|--arch)
			MATRIX_ARCH="${2:-}"
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

if ! validate_non_empty "--flutter-version" "$FLUTTER_VERSION"; then
	exit 2
fi

if ! validate_arch "$MATRIX_ARCH"; then
	exit 2
fi

setup_flutter_sdk "$FLUTTER_VERSION" "$FLUTTER_DIR" "$MATRIX_ARCH"
