#!/usr/bin/env bash
set -euo pipefail

# Packt das gebaute Linux-Bundle in verschiedene Formate.
# Unterstützte Formate: tar, deb, flatpak, appimage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cli-common.sh"
source "$SCRIPT_DIR/packaging-common.sh"

usage() {
	cat <<'EOF'
Usage:
	bash scripts/linux/lib/package-linux.sh [options]

Options:
	-a, --arch <x64|arm64>   Zielarchitektur (default: auto-detect)
	-n, --app-name <name>    Paket-/Anzeigename (default: kataglyphis-inference-engine)
			--formats <csv>   Zu erstellende Formate (default: tar,appimage,flatpak,deb)
			--strict          Bei fehlenden Tools/Packaging-Fehlern mit Exit 1 abbrechen
	-h, --help            Diese Hilfe anzeigen
EOF
}

FORMATS="${PACKAGE_FORMATS:-tar,appimage,flatpak,deb}"
STRICT_MODE=0
APP_NAME="kataglyphis-inference-engine"

MATRIX_ARCH="$(detect_arch)"

is_format_available() {
	local format="$1"
	case "$format" in
		tar) return 0 ;;
		deb) command -v dpkg-deb >/dev/null 2>&1 ;;
		flatpak) command -v flatpak >/dev/null 2>&1 && command -v flatpak-builder >/dev/null 2>&1 ;;
		appimage) command -v appimagetool >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 ;;
		*) return 1 ;;
	esac
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-a|--arch)
			MATRIX_ARCH="${2:-}"
			shift 2
			;;
		-n|--app-name)
			APP_NAME="${2:-}"
			shift 2
			;;
		--formats)
			FORMATS="${2:-}"
			shift 2
			;;
		--strict)
			STRICT_MODE=1
			shift
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

if ! validate_non_empty "--app-name" "$APP_NAME"; then
	exit 2
fi

if ! validate_arch "$MATRIX_ARCH"; then
	exit 2
fi

if [[ -z "$FORMATS" ]]; then
	echo "Error: --formats must not be empty" >&2
	exit 2
fi

IFS=',' read -r -a selected_formats <<< "$FORMATS"
failures=()
skipped=()
created=()

for raw_format in "${selected_formats[@]}"; do
	format="$(echo "$raw_format" | xargs | tr '[:upper:]' '[:lower:]')"

	case "$format" in
		tar)
			if ! is_format_available "$format"; then
				skipped+=("$format")
				echo "Warning: skipped '$format' (required tool missing)." >&2
				continue
			fi
			if ! package_linux_bundle_tar "$MATRIX_ARCH" "$APP_NAME"; then
				failures+=("$format")
			else
				created+=("$format")
			fi
			;;
		deb)
			if ! is_format_available "$format"; then
				skipped+=("$format")
				echo "Warning: skipped '$format' (required tool missing)." >&2
				continue
			fi
			if ! package_linux_bundle_deb "$MATRIX_ARCH" "$APP_NAME"; then
				failures+=("$format")
			else
				created+=("$format")
			fi
			;;
		flatpak)
			if ! is_format_available "$format"; then
				skipped+=("$format")
				echo "Warning: skipped '$format' (required tool missing)." >&2
				continue
			fi
			if ! package_linux_bundle_flatpak "$MATRIX_ARCH" "$APP_NAME"; then
				failures+=("$format")
			else
				created+=("$format")
			fi
			;;
		appimage)
			if ! is_format_available "$format"; then
				skipped+=("$format")
				echo "Warning: skipped '$format' (required tool missing)." >&2
				continue
			fi
			if ! package_linux_bundle_appimage "$MATRIX_ARCH" "$APP_NAME"; then
				failures+=("$format")
			else
				created+=("$format")
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

if [[ "${#created[@]}" -gt 0 ]]; then
	echo "Info: created package format(s): ${created[*]}"
fi

if [[ "${#skipped[@]}" -gt 0 ]]; then
	echo "Warning: skipped package format(s): ${skipped[*]}" >&2
	if [[ "$STRICT_MODE" -eq 1 ]]; then
		echo "Error: strict mode enabled and at least one format was skipped." >&2
		exit 1
	fi
fi

if [[ "${#failures[@]}" -gt 0 ]]; then
	echo "Error: packaging failed for format(s): ${failures[*]}" >&2
	exit 1
fi

if [[ "${#created[@]}" -eq 0 ]]; then
	echo "Error: no package artifacts were created." >&2
	exit 1
fi
