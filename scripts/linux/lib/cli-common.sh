#!/usr/bin/env bash

set -euo pipefail

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) echo "x64" ;;
  esac
}

validate_arch() {
  local arch="${1:-}"
  case "$arch" in
    x64|arm64) return 0 ;;
    *)
      echo "Error: --arch must be x64 or arm64 (got: ${arch:-<empty>})" >&2
      return 1
      ;;
  esac
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not found: $cmd" >&2
    return 1
  fi
}

run_nonfatal() {
  if ! "$@"; then
    echo "Warning: command failed (ignored): $*" >&2
    return 0
  fi
}

validate_non_empty() {
  local flag_name="${1:?flag name required}"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    echo "Error: ${flag_name} is required" >&2
    return 1
  fi
}

ensure_flutter_bin_on_path() {
  local flutter_dir="${1:-}"
  if [[ -n "$flutter_dir" && -x "${flutter_dir}/bin/flutter" ]]; then
    export PATH="${flutter_dir}/bin:$PATH"
  fi
}

resolve_strict_checks() {
  local strict_checks_value="${1:-}"
  if [[ -n "$strict_checks_value" ]]; then
    echo "$strict_checks_value"
    return 0
  fi

  if [[ "${CI:-}" == "true" ]]; then
    echo "1"
  else
    echo "0"
  fi
}

resolve_repo_root() {
  local preferred_root="${1:-/workspace}"
  if [[ -d "$preferred_root" ]]; then
    echo "$preferred_root"
  else
    pwd
  fi
}

# pubspec.yaml's package name is the single source of truth — AGENTS.md § 4.
resolve_app_name() {
  local lib_dir pubspec name
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for pubspec in "$(resolve_repo_root "${1:-}")/pubspec.yaml" "${lib_dir}/../../../pubspec.yaml"; do
    [[ -f "$pubspec" ]] || continue
    name="$(awk -F':[[:space:]]*' '/^name:[[:space:]]/{print $2; exit}' "$pubspec")"
    [[ -n "$name" ]] || continue
    echo "${name//_/-}"
    return 0
  done
  echo "[Error] could not read 'name:' from pubspec.yaml" >&2
  return 1
}
