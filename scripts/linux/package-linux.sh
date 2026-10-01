#!/usr/bin/env bash
set -euo pipefail

# Packages the built Linux bundle as tar, deb, flatpak and/or AppImage.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/linux/lib/cli-common.sh
source "$SCRIPT_DIR/lib/cli-common.sh"
# shellcheck source=scripts/linux/lib/packaging-common.sh
source "$SCRIPT_DIR/lib/packaging-common.sh"

# The fleet's run-every-gate-then-fail-once accumulator; packaging-common.sh already sourced antfrastructure.sh.
antfrastructure_source linux/scripts/01-core/gates.sh

# Probed up front: an older pin would otherwise fail mid-loop with "gate_skip: command not found".
if ! declare -F gate_skip >/dev/null; then
	echo "Error: the pinned ANTfrastructure's linux/scripts/01-core/gates.sh has no gate_skip." >&2
	echo "       This driver needs its third bucket: 'the tool for this format is not" >&2
	echo "       installed' is not a pass and not a failure, and counting it as either" >&2
	echo "       is what the rewrite of this file removed. Bump the submodule:" >&2
	echo "       git -C third_party/ANTfrastructure fetch origin && git -C third_party/ANTfrastructure checkout <sha>" >&2
	exit 1
fi

usage() {
	cat <<'EOF'
Usage:
	bash scripts/linux/package-linux.sh [options]

Options:
	-a, --arch <x64|arm64>   Zielarchitektur (default: auto-detect)
	-n, --app-name <name>    Paket-/Anzeigename (default: pubspec name)
			--formats <csv>   Zu erstellende Formate (default: tar,appimage,flatpak,deb)
			--strict          Bei fehlenden Tools/Packaging-Fehlern mit Exit 1 abbrechen
	-h, --help            Diese Hilfe anzeigen
EOF
}

FORMATS="${PACKAGE_FORMATS:-tar,appimage,flatpak,deb}"
STRICT_MODE=0
APP_NAME="$(resolve_app_name)"

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

# The hub's flatpak packager, then proof that the extra finish-args reached the built app's [Context].
package_flatpak_with_finish_args() {
	app_packaging_package_linux_bundle_flatpak "$@" || return 1
	local metadata="${KATAGLYPHIS_FLATPAK_WORKDIR:-/tmp/flatpak-work}/build-dir/metadata" arg key value
	local -a extra=()
	IFS=' ' read -r -a extra <<< "${KATAGLYPHIS_FLATPAK_FINISH_ARGS:-}"
	if [[ ! -f "$metadata" ]]; then
		echo "Error: no flatpak metadata at ${metadata}; the finish-args cannot be checked." >&2
		return 1
	fi
	echo "[Info] ${metadata}:"
	sed -n '/^\[Context\]/,/^$/p' "$metadata"
	for arg in ${extra[@]+"${extra[@]}"}; do
		case "$arg" in
			--device=*) key=devices; value="${arg#--device=}" ;;
			--socket=*) key=sockets; value="${arg#--socket=}" ;;
			--share=*) key=shared; value="${arg#--share=}" ;;
			*) continue ;;
		esac
		if ! grep -Eq "^${key}=(.*;)?${value};" "$metadata"; then
			echo "Error: ${arg} is not in the flatpak's [Context] ${key}= line." >&2
			return 1
		fi
	done
}

gate_reset "packaging ${APP_NAME} (${MATRIX_ARCH})"

for raw_format in "${selected_formats[@]}"; do
	format="$(echo "$raw_format" | xargs | tr '[:upper:]' '[:lower:]')"

	case "$format" in
		tar) packager=app_packaging_package_linux_bundle_tar ;;
		deb) packager=app_packaging_package_linux_bundle_deb ;;
		flatpak) packager=package_flatpak_with_finish_args ;;
		appimage) packager=app_packaging_package_linux_bundle_appimage ;;
		"") continue ;;
		*)
			# Fatal, not a skipped gate: an unknown format is the caller's typo, not a missing tool.
			echo "Error: unsupported format '$format'" >&2
			echo "Supported formats: tar, deb, flatpak, appimage" >&2
			exit 2
			;;
	esac

	if ! is_format_available "$format"; then
		gate_skip "$format" "required tool missing"
		continue
	fi

	run_gate "$format" "$packager" "$MATRIX_ARCH" "$APP_NAME"
done

# Without --strict a missing tool is tolerated (no defect on a dev box); a run with no artifact fails either way.
if [[ "$STRICT_MODE" -eq 1 ]]; then
	assert_gates
else
	assert_gates --tolerate-skips
fi
