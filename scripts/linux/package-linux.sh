#!/usr/bin/env bash
# set -euo pipefail

# Packt das gebaute Linux-Bundle in verschiedene Formate.
# Benötigte Umgebungsvariablen: MATRIX_ARCH, APP_NAME
# Unterstützte Formate: tar, deb, flatpak, appimage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/container-steps.sh"

usage() {
	cat <<'EOF'
Usage:
	bash scripts/linux/package-linux.sh [--formats tar,deb,flatpak,appimage]

Options:
			--formats <csv>   Zu erstellende Formate (default: tar)
	-h, --help            Diese Hilfe anzeigen

Environment:
	MATRIX_ARCH  Zielarchitektur (x64|arm64)
	APP_NAME     Paket-/Anzeigename
EOF
}

FORMATS="${PACKAGE_FORMATS:-tar}"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--formats)
			FORMATS="${2:-}"
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

if [[ -z "$FORMATS" ]]; then
	echo "Error: --formats must not be empty" >&2
	exit 2
fi

IFS=',' read -r -a selected_formats <<< "$FORMATS"
failures=()

for raw_format in "${selected_formats[@]}"; do
	format="$(echo "$raw_format" | xargs | tr '[:upper:]' '[:lower:]')"

	case "$format" in
		tar)
			if ! package_linux_bundle_tar; then
				failures+=("$format")
			fi
			;;
		deb)
			if ! package_linux_bundle_deb; then
				failures+=("$format")
			fi
			;;
		flatpak)
			if ! package_linux_bundle_flatpak; then
				failures+=("$format")
			fi
			;;
		appimage)
			if ! package_linux_bundle_appimage; then
				failures+=("$format")
			fi
			;;
		"")
			;;
		*)
			echo "Error: unsupported format '$format'" >&2
			echo "Supported formats: tar, deb, flatpak, appimage" >&2
			exit 2
			;;
	esac
done

if [[ "${#failures[@]}" -gt 0 ]]; then
	echo "Error: packaging failed for format(s): ${failures[*]}" >&2
	exit 1
fi
