#!/usr/bin/env bash
# One flag loop for this repo's entry scripts, usable before the hub submodule exists; it does not validate what it assigns.

_entry_options_help() {
  if declare -F -- "$1" >/dev/null; then
    "$1"
  else
    printf 'usage: %s %s\n' "$0" "$1"
  fi
}

# parse_entry_options <usage-text-or-fn> <other-fn-or-empty> <spec>... -- "$@"; spec forms and contract: docs/source/project-operations.md#entry-script-flags
parse_entry_options() {
  local usage="$1" other="$2" spec flag target
  local -A _entry_values=() _entry_phrases=() _entry_switches=()
  shift 2
  while [[ "$1" != -- ]]; do
    spec="$1"
    if [[ "$spec" == +* ]]; then
      spec="${spec#+}"
      _entry_switches[${spec%%=*}]="${spec#*=}"
      shift
      continue
    fi
    flag="${spec%%=*}"
    target="${spec#*=}"
    _entry_values[$flag]="${target%%:*}"
    if [[ "$target" == *:* ]]; then _entry_phrases[$flag]="${target#*:}"; fi
    shift
  done
  shift
  while (($#)); do
    case "$1" in -h|--help) _entry_options_help "$usage"; exit 0 ;; esac
    if [[ -n "$1" && -n "${_entry_switches[$1]:-}" ]]; then
      printf -v "${_entry_switches[$1]%%=*}" '%s' "${_entry_switches[$1]#*=}"
      shift
      continue
    fi
    if [[ -n "$1" && -n "${_entry_values[$1]:-}" ]]; then
      if (($# < 2)) || [[ -n "${_entry_phrases[$1]:-}" && -z "$2" ]]; then
        printf '%s needs %s\n' "$1" "${_entry_phrases[$1]:-a value}" >&2
        exit 1
      fi
      printf -v "${_entry_values[$1]}" '%s' "$2"
      shift 2
      continue
    fi
    if [[ -n "$other" ]] && "$other" "$1"; then
      shift
      continue
    fi
    printf 'unknown argument: %s\n' "$1" >&2
    exit 2
  done
}
