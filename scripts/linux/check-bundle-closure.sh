#!/usr/bin/env bash
# Grades the runtime closure of a built bundle, headlessly: every DT_NEEDED is
# bundled or in the system allowlist (lib/bundle-runtime.sh), every lib with a
# bundled sibling has an $ORIGIN RUNPATH to it (RUNPATH is not transitive), the
# GStreamer plugins are present (nothing DT_NEEDs them), and ANTfrastructure's G6
# census proves every ONNX Runtime binary and user in it.
# Usage: scripts/linux/check-bundle-closure.sh [--arch x64|arm64]
#            [--build-mode MODE] [--bundle-dir DIR] [--ort-reference DIR]
# Detail: docs/source/camera-streaming.md § Relocatable Linux bundles.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/cli-common.sh"
# shellcheck source=scripts/linux/lib/bundle-runtime.sh
source "$SCRIPT_DIR/lib/bundle-runtime.sh"
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "$SCRIPT_DIR/lib/antfrastructure.sh"

MATRIX_ARCH="$(detect_arch)"
BUILD_MODE="release"
BUNDLE_DIR=""
# G6's chain reference; empty = the image's chain ORT, which is what the lane grades against.
ORT_REFERENCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--arch) MATRIX_ARCH="${2:-}"; shift 2 ;;
    --build-mode) BUILD_MODE="${2:-}"; shift 2 ;;
    --bundle-dir) BUNDLE_DIR="${2:-}"; shift 2 ;;
    --ort-reference) ORT_REFERENCE="${2:?--ort-reference needs a directory}"; shift 2 ;;
    -h|--help)
      printf 'usage: %s [--arch x64|arm64] [--build-mode debug|profile|release] [--bundle-dir DIR] [--ort-reference DIR]\n' "$0"
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

# Owner rule 2026-09-23: the bundle's only ORT is the image's chain build (the hub's G6 decides).
# It runs on an ORT-named file or any file naming G6's ORT ABI, so a user with no ORT beside it fails.
ort_census_args=()
if [[ -n "$ORT_REFERENCE" ]]; then
  ort_census_args=(--reference "$ORT_REFERENCE")
fi
ort_user_rc=0
grep -rqaF -e OrtGetApiBase -e CreateEpFactories -e RegisterCustomOps -- "$BUNDLE_DIR" || ort_user_rc=$?
# Only rc 1 means "no ORT user": a read error (2) runs the census instead of skipping it.
if [[ "$ort_user_rc" -ne 1 || -n "$(find "$BUNDLE_DIR" -name 'libonnxruntime*' -print -quit)" ]]; then
  if ! ort_census="$(antfrastructure_path linux/scripts/06-packaging/check-ort-provenance.sh)"; then
    printf 'FAIL the ONNX Runtime census (G6) needs ANTfrastructure from its ORT single-source commit of 2026-09-23 (third_party/ANTfrastructure/docs/onnxruntime-single-source.md): move third_party/ANTfrastructure to it or later\n'
    failures=$((failures + 1))
  elif ! bash "$ort_census" ${ort_census_args[@]+"${ort_census_args[@]}"} "$BUNDLE_DIR"; then
    failures=$((failures + 1))
  fi
fi

if [[ "$failures" -gt 0 ]]; then
  printf 'bundle closure: %d failure(s) across %d ELF file(s) and %d plugin(s)\n' \
    "$failures" "$checked" "$found_plugins" >&2
  exit 1
fi
printf 'bundle closure OK: %d ELF file(s), %d GStreamer plugin(s)\n' "$checked" "$found_plugins"
