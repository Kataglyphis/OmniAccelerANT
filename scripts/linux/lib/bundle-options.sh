#!/usr/bin/env bash

# These two gates only differ in their bundle path flag.
# shellcheck source=scripts/linux/lib/entry-options.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/entry-options.sh"

_bundle_gate_usage() {
  case "$_bundle_gate_kind" in
    gst) printf 'usage: %s [--arch x64|arm64] [--build-mode debug|profile|release] [--bundle-dir DIR]\n' "$0" ;;
    knt) printf 'usage: %s [--arch x64|arm64] [--build-mode debug|profile|release] [--bundle-lib DIR]\n' "$0" ;;
  esac
}

parse_bundle_gate_options() {
  local _bundle_gate_kind="$1" bundle_spec
  shift
  case "$_bundle_gate_kind" in
    gst) bundle_spec='--bundle-dir=bundle_dir:a value' ;;
    knt) bundle_spec='--bundle-lib=bundle_lib:a value' ;;
    *) printf 'unknown bundle gate: %s\n' "$_bundle_gate_kind" >&2; return 2 ;;
  esac
  parse_entry_options _bundle_gate_usage '' '--arch=matrix_arch:a value' '--build-mode=build_mode:a value' "$bundle_spec" -- "$@"
}
