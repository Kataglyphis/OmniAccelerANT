#!/usr/bin/env bash

# The hub owns value movement; these two gates only differ in their bundle path flag.
# shellcheck source=scripts/linux/lib/antfrastructure.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/antfrastructure.sh"
antfrastructure_source linux/scripts/lib/cli-value-options.sh

_bundle_gate_usage() {
  case "$1" in
    gst) printf 'usage: %s [--arch x64|arm64] [--build-mode debug|profile|release] [--bundle-dir DIR]\n' "$0" ;;
    knt) printf 'usage: %s [--arch x64|arm64] [--build-mode debug|profile|release] [--bundle-lib DIR]\n' "$0" ;;
  esac
}

_bundle_gate_other_arg() {
  case "$1" in
    -h|--help) _bundle_gate_usage "$_bundle_gate_kind"; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
}

_bundle_gate_check_values() {
  local -n _bundle_gate_known="$1"
  shift
  while (($#)); do
    case "$1" in -h|--help) return 0 ;; esac
    if [[ -z "${_bundle_gate_known[$1]:-}" ]]; then return 0; fi
    if (($# < 2)) || [[ -z "$2" ]]; then
      printf '%s needs a value\n' "$1" >&2
      return 1
    fi
    shift 2
  done
}

parse_bundle_gate_options() {
  local _bundle_gate_kind="$1"
  shift
  local -A _bundle_gate_values=([--arch]=matrix_arch [--build-mode]=build_mode)
  local -a _bundle_gate_remaining=()
  case "$_bundle_gate_kind" in
    gst) _bundle_gate_values[--bundle-dir]=bundle_dir ;;
    knt) _bundle_gate_values[--bundle-lib]=bundle_lib ;;
    *) printf 'unknown bundle gate: %s\n' "$_bundle_gate_kind" >&2; return 2 ;;
  esac
  _bundle_gate_check_values _bundle_gate_values "$@" || return 1
  parse_cli_value_options _bundle_gate_values _bundle_gate_remaining _bundle_gate_other_arg "$@"
}
