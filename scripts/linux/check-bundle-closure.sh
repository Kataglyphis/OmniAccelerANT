#!/usr/bin/env bash
# Grades the runtime closure of a built bundle, headlessly. Two checks: every
# DT_NEEDED of the runner and of every bundle lib is bundled or in the documented
# system allowlist (lib/bundle-runtime.sh), and every lib with a bundled sibling
# carries an $ORIGIN-relative RUNPATH to it - because RUNPATH is not transitive.
# The runtime-loaded GStreamer plugins are checked for presence only: nothing
# DT_NEEDs them, so readelf cannot prove they are loadable.
# Usage: scripts/linux/check-bundle-closure.sh [--arch x64|arm64]
#            [--build-mode MODE] [--bundle-dir DIR]
# Detail: docs/source/camera-streaming.md § Relocatable Linux bundles.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/cli-common.sh"
# shellcheck source=scripts/linux/lib/bundle-runtime.sh
source "$SCRIPT_DIR/lib/bundle-runtime.sh"

MATRIX_ARCH="$(detect_arch)"
BUILD_MODE="release"
BUNDLE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--arch) MATRIX_ARCH="${2:-}"; shift 2 ;;
    --build-mode) BUILD_MODE="${2:-}"; shift 2 ;;
    --bundle-dir) BUNDLE_DIR="${2:-}"; shift 2 ;;
    -h|--help)
      printf 'usage: %s [--arch x64|arm64] [--build-mode debug|profile|release] [--bundle-dir DIR]\n' "$0"
      exit 0
      ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if ! validate_arch "$MATRIX_ARCH"; then
  exit 2
fi
if [[ -z "$BUNDLE_DIR" ]]; then
  BUNDLE_DIR="$REPO_ROOT/build/linux/$MATRIX_ARCH/$BUILD_MODE/bundle"
fi
bundle_lib="$BUNDLE_DIR/lib"
plugin_dir="$bundle_lib/gstreamer-1.0"

if [[ ! -d "$bundle_lib" ]]; then
  printf 'Error: no bundle at %s (run the Flutter build first)\n' "$BUNDLE_DIR" >&2
  exit 1
fi

require_cmd readelf

failures=0
checked=0

check_one_elf() {
  local file="$1" location="$2" soname token
  local -a needed_bundled=() missing=()

  if ! readelf -h "$file" >/dev/null 2>&1; then
    printf 'FAIL %s is not an ELF file\n' "${file#"$BUNDLE_DIR"/}"
    failures=$((failures + 1))
    return 0
  fi
  checked=$((checked + 1))

  while IFS= read -r soname; do
    [[ -n "$soname" ]] || continue
    if [[ -e "$bundle_lib/$soname" || -e "$plugin_dir/$soname" ]]; then
      needed_bundled+=("$soname")
    elif ! is_system_soname "$soname"; then
      missing+=("$soname")
    fi
  done < <(elf_needed "$file")

  for soname in "${missing[@]}"; do
    printf 'FAIL %s needs %s: neither bundled nor provided by the declared system dependencies\n' \
      "${file#"$BUNDLE_DIR"/}" "$soname"
    failures=$((failures + 1))
  done

  if [[ ${#needed_bundled[@]} -eq 0 ]]; then
    return 0
  fi
  case "$location" in
    root) token='$ORIGIN/lib' ;;
    plugin) token='$ORIGIN/..' ;;
    *) token='$ORIGIN' ;;
  esac
  if ! runpath_has_token "$file" "$token"; then
    printf 'FAIL %s needs %s but its RUNPATH lacks %s (bundled is not reachable)\n' \
      "${file#"$BUNDLE_DIR"/}" "${needed_bundled[*]}" "$token"
    failures=$((failures + 1))
  fi
  return 0
}

for file in "$BUNDLE_DIR"/*; do
  [[ -f "$file" && -x "$file" ]] || continue
  check_one_elf "$file" root
done
for file in "$bundle_lib"/*.so*; do
  [[ -f "$file" ]] || continue
  check_one_elf "$file" lib
done
found_plugins=0
for plugin in "${GST_BUNDLED_PLUGIN_NAMES[@]}"; do
  if [[ ! -f "$plugin_dir/libgst${plugin}.so" ]]; then
    printf 'FAIL GStreamer plugin libgst%s.so is not bundled; its pipeline elements would read as missing\n' "$plugin"
    failures=$((failures + 1))
  else
    found_plugins=$((found_plugins + 1))
  fi
done
for file in "$plugin_dir"/*.so; do
  [[ -f "$file" ]] || continue
  check_one_elf "$file" plugin
done

if [[ "$failures" -gt 0 ]]; then
  printf 'bundle closure: %d failure(s) across %d ELF file(s) and %d plugin(s)\n' \
    "$failures" "$checked" "$found_plugins" >&2
  exit 1
fi
printf 'bundle closure OK: %d ELF file(s), %d GStreamer plugin(s)\n' "$checked" "$found_plugins"
