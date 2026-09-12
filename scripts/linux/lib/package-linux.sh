#!/usr/bin/env bash
set -euo pipefail

# Packt das gebaute Linux-Bundle in verschiedene Formate.
# Unterstützte Formate: tar, deb, flatpak, appimage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cli-common.sh"
source "$SCRIPT_DIR/packaging-common.sh"

# gate_reset / run_gate / gate_skip / assert_gates — the fleet's "run every
# gate, then fail once" accumulator. packaging-common.sh has already sourced
# antfrastructure.sh, which is what finds the submodule.
antfrastructure_source linux/scripts/01-core/gates.sh

# gate_skip is NEWER than the rest of that file (2026-09-09), and this driver is
# what it was added for: a packaging format whose tool is absent is neither a
# pass nor a failure, and gates.sh had only two buckets. Probed here rather than
# discovered at the first missing tool, where a pin that predates it would read
# as "gate_skip: command not found" from inside the loop — and, before this
# check existed, only after some formats had already been built.
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
	bash scripts/linux/lib/package-linux.sh [options]

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

# ONE accumulator, and it is upstream's. What stood here was a fourth private
# copy of it — failures/skipped/created arrays wrapped around four case arms
# that differed only in which package_linux_bundle_* they called — and the
# header of ANTfrastructure's linux/scripts/01-core/gates.sh names that
# reinvention as the thing it exists to end.
gate_reset "packaging ${APP_NAME} (${MATRIX_ARCH})"

for raw_format in "${selected_formats[@]}"; do
	format="$(echo "$raw_format" | xargs | tr '[:upper:]' '[:lower:]')"

	# The whole of what the four arms used to differ by.
	case "$format" in
		tar) packager=package_linux_bundle_tar ;;
		deb) packager=package_linux_bundle_deb ;;
		flatpak) packager=package_linux_bundle_flatpak ;;
		appimage) packager=package_linux_bundle_appimage ;;
		"") continue ;;
		*)
			# Still fatal on the spot, and deliberately not a skipped gate: a
			# format nobody implements is a typo in the caller's --formats, not
			# a missing tool on this machine.
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

# The verdict, once. Every branch of the tail this replaces is now upstream's:
#
#   * "Info: created package format(s)" is the batch's passing gates — run_gate
#     prints `== tar: ok ==` as each one lands and assert_gates counts them.
#   * "packaging failed for format(s)" is assert_gates naming every failure,
#     and it still names ALL of them: run_gate records rather than aborts, so a
#     broken deb no longer hides whether appimage would have worked.
#   * --strict is the DEFAULT upstream: assert_gates reds a skip unless it is
#     handed --tolerate-skips, so tolerance is the thing you have to ask for
#     and the thing that greps. Without --strict this driver asks for it,
#     because a format whose tool is absent on a dev box is not a defect in
#     the tree; in CI, where --strict is passed, it is.
#   * "no package artifacts were created" is assert_gates refusing to report
#     green over a batch in which nothing ran. That case is reached when every
#     requested format was skipped, and --tolerate-skips does NOT cover it: a
#     run that produced no artifact has nothing to ship, strict or not.
if [[ "$STRICT_MODE" -eq 1 ]]; then
	assert_gates
else
	assert_gates --tolerate-skips
fi
